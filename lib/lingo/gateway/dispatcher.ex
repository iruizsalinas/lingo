defmodule Lingo.Gateway.Dispatcher do
  @moduledoc false

  require Logger

  alias Lingo.Type.Interaction

  @spec dispatch(atom() | {:unknown_event, String.t()}, map()) :: :ok
  def dispatch(event, data) do
    Lingo.Voice.Manager.dispatch(event, data)

    parsed =
      try do
        update_and_parse(event, data)
      rescue
        e ->
          Logger.error("Dispatcher crash on #{inspect(event)}: #{Exception.message(e)}")
          data
      end

    if event == :ready, do: Lingo.Bot.Sync.register_on_ready()

    case Lingo.Collector.Match.try_match(event, parsed) do
      :collected -> :ok
      :miss -> dispatch_to_bot(event, parsed)
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

  # updates the cache and builds the event payload in one pass; events no
  # parser knows reach the bot as raw maps
  defp update_and_parse(event, data) do
    Enum.reduce_while(@parsers, data, fn parser, data ->
      case parser.parse(event, data) do
        :skip -> {:cont, data}
        parsed -> {:halt, parsed}
      end
    end)
  end

  # forward to user's bot module

  defp dispatch_to_bot(:interaction_create, %Interaction{} = interaction) do
    Lingo.Bot.Runner.interaction(interaction)
  end

  defp dispatch_to_bot(event, data), do: Lingo.Bot.Runner.event(event, data)
end
