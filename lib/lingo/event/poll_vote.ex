defmodule Lingo.Event.PollVote do
  @moduledoc "The payload of `:message_poll_vote_add` and `:message_poll_vote_remove`."

  @type t :: %__MODULE__{
          user_id: String.t(),
          channel_id: String.t(),
          message_id: String.t(),
          guild_id: String.t() | nil,
          answer_id: integer()
        }

  defstruct [:user_id, :channel_id, :message_id, :guild_id, :answer_id]

  @doc false
  def new(nil), do: nil
  def new(data) when is_map(data), do: Lingo.Type.Parse.fields(__MODULE__, data)
end
