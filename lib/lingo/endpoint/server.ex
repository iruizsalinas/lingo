defmodule Lingo.Endpoint.Server do
  @moduledoc false

  # A small HTTP server for Lingo.Endpoint, on OTP's :httpd: POSTs to the
  # interactions and events paths go to Lingo.Endpoint, anything else is
  # refused. :httpd calls do/1 in a process per request; the bot is found by
  # the port the request came in on.

  use GenServer

  require Record

  Record.defrecordp(:mod, Record.extract(:mod, from_lib: "inets/include/httpd.hrl"))

  @max_body 8 * 1024 * 1024

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "The port a running server listens on."
  def port(server), do: GenServer.call(server, :port)

  @impl true
  def init(opts) do
    # so terminate/2 stops the :httpd service with us
    Process.flag(:trap_exit, true)
    bot = Keyword.fetch!(opts, :bot)
    endpoint = Keyword.fetch!(opts, :endpoint)
    routes = routes(endpoint)

    config = [
      port: Keyword.fetch!(endpoint, :port),
      bind_address: Keyword.get(endpoint, :ip, {0, 0, 0, 0}),
      server_name: ~c"lingo",
      server_root: String.to_charlist(System.tmp_dir!()),
      document_root: String.to_charlist(System.tmp_dir!()),
      modules: [__MODULE__],
      max_body_size: @max_body
    ]

    with {:ok, httpd} <- :inets.start(:httpd, config) do
      Process.link(httpd)
      port = :httpd.info(httpd)[:port]
      # requests only arrive once the caller knows the port, after this
      :persistent_term.put({__MODULE__, port}, {bot, routes})
      {:ok, %{httpd: httpd, port: port}}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  @impl true
  def handle_info({:EXIT, httpd, reason}, %{httpd: httpd} = state), do: {:stop, reason, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    :persistent_term.erase({__MODULE__, state.port})
    :inets.stop(:httpd, state.httpd)
  end

  defp routes(endpoint) do
    %{
      Keyword.get(endpoint, :interactions_path, "/interactions") => :interaction,
      Keyword.get(endpoint, :events_path, "/events") => :event
    }
  end

  @doc false
  def unquote(:do)(data) do
    request = mod(data)
    port = :httpd_util.lookup(mod(data, :config_db), :port)
    path = request[:request_uri] |> to_string() |> URI.parse() |> Map.get(:path)

    {status, headers, body} =
      with {bot, routes} <- :persistent_term.get({__MODULE__, port}, nil),
           kind when kind != nil <- routes[path] do
        handle(request[:method], kind, bot, request)
      else
        _ -> {404, [], ""}
      end

    {:proceed, [{:response, {:response, response_headers(status, headers, body), [body]}}]}
  end

  defp handle(~c"POST", kind, bot, request) do
    headers = request[:parsed_header]
    body = IO.iodata_to_binary(request[:entity_body])

    apply(Lingo.Endpoint, kind, [bot, headers, body])
  end

  defp handle(_method, _kind, _bot, _request), do: {405, [], ""}

  defp response_headers(status, headers, body) do
    content_type = List.keyfind(headers, "content-type", 0, {nil, "text/plain"}) |> elem(1)

    [
      code: status,
      content_type: String.to_charlist(content_type),
      content_length: Integer.to_charlist(byte_size(body))
    ]
  end
end
