defmodule Lingo.Endpoint do
  @moduledoc """
  Receiving interactions and webhook events over HTTP, instead of (or next
  to) the gateway.

  Discord can deliver interactions to an *Interactions Endpoint URL* and app
  events (an app added or removed, entitlements, lobby messages...) to a
  *Webhook Events URL*, both set in the Developer Portal. Every request is
  signed; Lingo checks the signature with your app's public key and answers
  Discord's checks. Interactions reach your bot's callbacks as usual and
  events reach `c:Lingo.Bot.handle_event/2`.

  ## Configuration

      {MyBot,
       token: System.fetch_env!("BOT_TOKEN"),
       endpoint: [public_key: System.fetch_env!("DISCORD_PUBLIC_KEY"), port: 4000],
       gateway: false}

  `endpoint` options:

    * `:public_key` (required) - the app's public key, from the Developer Portal
    * `:port` - starts a small HTTP server (OTP's `:httpd`) on this port,
      answering `POST`s on `:interactions_path` (default `"/interactions"`)
      and `:events_path` (default `"/events"`). Put it behind a reverse
      proxy for HTTPS. Without `:port`, call `interaction/3` and `event/3`
      from your own web server.
    * `:ip` - the address the server listens on (default `{0, 0, 0, 0}`)

  `gateway: false` runs the bot without a gateway connection: commands and
  components work, gateway events don't arrive, and `:register_commands`
  registers when the bot starts.

  Once an Interactions Endpoint URL is set, Discord sends interactions there
  and no longer over the gateway, so the endpoint has to be served even when
  the gateway runs too. Entitlement events come both through the gateway and
  as webhook events: a bot with both gets each one twice.

  ## From your own web server

  Hand over the request headers and the raw body, before anything parses
  it, and send back what you get. With Plug:

      def call(%{method: "POST", path_info: ["interactions"]} = conn, _opts) do
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        {status, headers, resp} = Lingo.Endpoint.interaction(MyBot, conn.req_headers, body)

        conn |> Plug.Conn.merge_resp_headers(headers) |> Plug.Conn.send_resp(status, resp)
      end

  ## How interactions are answered

  An interaction is answered through the interaction callback, the same as
  with the gateway, and the HTTP request is held open until it has been (up
  to about 2.5 seconds), then answered with `202` and no body, as Discord
  documents for interactions answered through the callback. So
  `Lingo.Context` and collectors work unchanged, files and large responses
  included. An interaction nobody answers in time gets the `202` anyway,
  and Discord shows it as failed, as it does with the gateway.
  """

  alias Lingo.Bot.Runner
  alias Lingo.Endpoint.{Pending, Signature}
  alias Lingo.Event.Catalog
  alias Lingo.Instance

  @json [{"content-type", "application/json"}]
  @answer_wait 2_500

  @typedoc "The bot's name: its module, or the `:name` it was started with."
  @type bot :: atom()

  @typedoc "Headers as a list or map of `{name, value}`, names in any case."
  @type headers :: Enumerable.t()
  @type response :: {status :: pos_integer(), [{String.t(), String.t()}], body :: binary()}

  @doc """
  Handles a request to the Interactions Endpoint URL: answers Discord's
  `PING`, rejects bad signatures with `401`, and hands the interaction to
  the bot, returning once it's answered.

  Raises `ArgumentError` when `bot` wasn't started with an `:endpoint`.
  """
  @spec interaction(bot(), headers(), binary()) :: response()
  def interaction(bot, headers, body) when is_atom(bot),
    do: Instance.with_current(bot, fn -> handle_interaction(headers, body) end)

  defp handle_interaction(headers, body) do
    with {:ok, payload} <- verified(headers, body) do
      case payload do
        %{"type" => 1} -> {200, @json, ~s({"type":1})}
        %{"type" => _, "id" => id} -> dispatch_interaction(id, payload)
        _other -> {400, @json, ~s({"error":"bad request"})}
      end
    end
  end

  @doc """
  Handles a request to the Webhook Events URL: answers Discord's `PING`,
  rejects bad signatures with `401`, and hands the event to the bot's
  `c:Lingo.Bot.handle_event/2`, as `:application_authorized`,
  `:entitlement_create`, `:lobby_message_create` and so on (see
  `Lingo.Event`).

  Raises `ArgumentError` when `bot` wasn't started with an `:endpoint`.
  """
  @spec event(bot(), headers(), binary()) :: response()
  def event(bot, headers, body) when is_atom(bot),
    do: Instance.with_current(bot, fn -> handle_event(headers, body) end)

  defp handle_event(headers, body) do
    with {:ok, payload} <- verified(headers, body) do
      case payload do
        %{"type" => 0} ->
          {204, @json, ""}

        %{"type" => 1, "event" => %{"type" => type} = event} ->
          deliver_event(Catalog.webhook_name(type), event["data"] || %{})
          {204, @json, ""}

        _other ->
          {400, @json, ~s({"error":"bad request"})}
      end
    end
  end

  @doc "Whether a request carries Discord's valid signature for `public_key`."
  @spec valid_signature?(headers(), binary(), String.t()) :: boolean()
  def valid_signature?(headers, body, public_key),
    do: Signature.valid?(Signature.headers(headers), body, public_key)

  defp verified(headers, body) do
    if valid_signature?(headers, body, public_key()) do
      case JSON.decode(body) do
        {:ok, payload} when is_map(payload) -> {:ok, payload}
        _invalid -> {400, @json, ~s({"error":"bad request"})}
      end
    else
      {401, @json, ~s({"error":"invalid request signature"})}
    end
  end

  defp public_key do
    case Instance.get(:endpoint, nil) do
      [_ | _] = endpoint ->
        Keyword.fetch!(endpoint, :public_key)

      _ ->
        raise ArgumentError,
              "#{inspect(Instance.current())} has no :endpoint option with a :public_key"
    end
  end

  defp dispatch_interaction(id, payload) do
    bot = Instance.current()
    Pending.watch(bot, id)

    try do
      Lingo.Gateway.Dispatcher.dispatch(:interaction_create, payload)
      Pending.await(id, @answer_wait)
    after
      Pending.unwatch(bot, id)
    end

    {202, @json, ""}
  end

  defp deliver_event({:unknown, _type} = event, data),
    do: Runner.event(:unknown, Catalog.parse(event, data))

  defp deliver_event(event, data) do
    Runner.event(event, Catalog.parse(event, data))
  rescue
    e -> Runner.parse_failed(event, data, e, __STACKTRACE__)
  end
end
