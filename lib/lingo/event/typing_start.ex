defmodule Lingo.Event.TypingStart do
  @moduledoc "The payload of `:typing_start`. `member` is set in guilds."

  alias Lingo.Type.{Member, Parse}

  @type t :: %__MODULE__{
          channel_id: String.t(),
          guild_id: String.t() | nil,
          user_id: String.t(),
          timestamp: DateTime.t(),
          member: Member.t() | nil
        }

  defstruct [:channel_id, :guild_id, :user_id, :timestamp, :member]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    guild_id = data["guild_id"]

    %__MODULE__{
      channel_id: data["channel_id"],
      guild_id: guild_id,
      user_id: data["user_id"],
      timestamp: Parse.unix(data["timestamp"]),
      member: data["member"] && Member.new(Parse.put_guild_id(data["member"], guild_id))
    }
  end
end
