defmodule Lingo.EventError do
  @moduledoc """
  An event Lingo couldn't build a payload for, such as one whose shape
  Discord changed. It never reaches `c:Lingo.Bot.handle_event/2`, whose
  clauses expect the parsed payload; `c:Lingo.Bot.handle_error/2` gets this
  error with `{event, data}`, Discord's raw data with string keys.

  `exception` is what parsing raised.
  """

  defexception [:event, :data, :exception, :message]

  @type t :: %__MODULE__{
          event: atom(),
          data: term(),
          exception: Exception.t(),
          message: String.t()
        }

  @doc false
  @spec new(atom(), term(), Exception.t()) :: t()
  def new(event, data, exception) do
    %__MODULE__{
      event: event,
      data: data,
      exception: exception,
      message: "could not parse #{inspect(event)}: #{Exception.message(exception)}"
    }
  end
end
