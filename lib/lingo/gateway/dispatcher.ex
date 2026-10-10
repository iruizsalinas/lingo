defmodule Lingo.Gateway.Dispatcher do
  @moduledoc false

  # Where every event goes once it's off the wire: voice gets its share, the
  # cache is updated, the payload is built (see Lingo.Event), and collectors
  # or the bot get it. An event that fails to parse reaches the bot's
  # handle_error/2 instead of handle_event/2.

  alias Lingo.Bot.Runner
  alias Lingo.Event.Catalog
  alias Lingo.Type.Interaction

  @spec dispatch(atom() | {:unknown, String.t()}, map()) :: :ok
  def dispatch(event, data) do
    Lingo.Voice.Manager.dispatch(event, data)

    unless Catalog.payload(event) == :internal do
      try do
        payload(event, data)
      rescue
        e -> Runner.parse_failed(event, data, e, __STACKTRACE__)
      else
        payload -> deliver(name(event), payload)
      end
    end

    :ok
  end

  @parsers [
    __MODULE__.Guild,
    __MODULE__.Member,
    __MODULE__.Channel,
    __MODULE__.Message,
    __MODULE__.Other
  ]

  @doc """
  Updates the cache and builds the payload in one pass. Events that touch no
  cache are built from the catalog alone.
  """
  @spec payload(atom() | {:unknown, String.t()}, map()) :: term()
  def payload(event, data) do
    Enum.find_value(@parsers, fn parser ->
      case parser.parse(event, data) do
        :skip -> nil
        payload -> {:ok, payload}
      end
    end)
    |> case do
      {:ok, payload} -> payload
      nil -> Catalog.parse(event, data)
    end
  end

  defp name({:unknown, _type}), do: :unknown
  defp name(event), do: event

  defp deliver(event, payload) do
    case Lingo.Collector.Match.try_match(event, payload) do
      :collected -> :ok
      :miss -> to_bot(event, payload)
    end
  end

  defp to_bot(:interaction_create, %Interaction{} = interaction),
    do: Runner.interaction(interaction)

  defp to_bot(event, payload), do: Runner.event(event, payload)
end
