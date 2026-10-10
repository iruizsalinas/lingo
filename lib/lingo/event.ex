defmodule Lingo.Event do
  alias Lingo.Event.Catalog

  table = fn events ->
    rows =
      for {_type, name, payload} <- events, payload != :internal do
        shape =
          case payload do
            # no "|" in here: it would split the table cell
            {:update, module} ->
              "`%{old: old, new: new}` of `#{inspect(module)}`"

            module ->
              "`#{inspect(module)}`"
          end

        "| `#{inspect(name)}` | #{shape} |"
      end

    Enum.join(["| Event | Payload |", "| --- | --- |" | rows], "\n")
  end

  @moduledoc """
  The events `c:Lingo.Bot.handle_event/2` receives: every one Discord sends,
  named as Discord names it, lowercased.

      def handle_event(:message_create, %Lingo.Type.Message{content: "!ping"} = msg),
        do: Lingo.Api.Message.create(msg.channel_id, "Pong!")

      def handle_event(:message_delete, %Lingo.Event.MessageDelete{old: %{content: content}}),
        do: Logger.info("deleted: \#{content}")

      def handle_event(:message_update, %{old: old, new: new}), do: ...

  A payload takes one of three shapes:

    * **a resource** (`Lingo.Type.Message`, `Lingo.Type.Channel`, ...), the
      same struct `Lingo.Api` returns, when Discord sends one: creates, and
      deletes that carry the whole object, such as `:channel_delete`.
    * **`%{old: t | nil, new: t}`** for updates of a resource.
    * **a struct of its own** in `Lingo.Event`, named after Discord's event
      objects, for everything else: deletes that carry only ids, bans,
      reactions, typing and so on.

  ## `old`

  Updates, and deletes that carry only ids, include `old`: the resource as
  the cache held it just before the change. It's `nil` when it wasn't
  cached: the resource is disabled (nothing is cached by default, see
  `Lingo.Cache`), filtered out or evicted, or Lingo never saw it. So `nil`
  means unknown, never empty, and a handler that needs `old` should match
  `nil` too. Without a cache, `new` in `:message_update` holds only the
  fields Discord sent.

  ## Unknown events

  Events newer than Lingo arrive as `:unknown`, with a `Lingo.Event.Unknown`
  holding Discord's name and raw payload.

  Lingo's own happenings (shards connecting and disconnecting, API rate
  limits) are not events but `Lingo.Telemetry` events; to wait until every
  shard is up, use `Lingo.Gateway.await_ready/1`.

  ## Gateway events

  #{table.(Catalog.gateway())}

  ## Webhook events

  These come through `Lingo.Endpoint`'s webhook events URL. Entitlement
  events come both ways: a bot with the gateway and webhook events on gets
  each one twice, so deduplicate by id or subscribe to one.

  #{table.(Catalog.webhook())}
  """

  union = fn types -> types |> Enum.reverse() |> Enum.reduce(&{:|, [], [&1, &2]}) end
  events = Catalog.gateway() ++ Catalog.webhook()

  names =
    for {_type, name, payload} <- events, payload != :internal, uniq: true, do: name

  payloads =
    for {_type, _name, payload} <- events, payload != :internal, uniq: true do
      case payload do
        {:update, module} -> quote(do: update(unquote(module).t()))
        module -> quote(do: unquote(module).t())
      end
    end

  @typedoc "An update's payload: the resource before (from the cache, or `nil`) and after."
  @type update(t) :: %{old: t | nil, new: t}

  @typedoc "An event's name."
  @type name :: unquote(union.(names ++ [:unknown]))

  @typedoc "An event's payload. The table above says which goes with which name."
  @type payload :: unquote(union.(payloads ++ [quote(do: Lingo.Event.Unknown.t())]))
end
