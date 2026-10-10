defmodule Lingo.Event.Reaction do
  @moduledoc """
  The payload of `:message_reaction_add`, `:message_reaction_remove` and
  `:message_reaction_remove_emoji` (which has no `user_id` or `member`).
  `burst` marks super reactions.
  """

  alias Lingo.Type.{Emoji, Member, Parse}

  @type t :: %__MODULE__{
          user_id: String.t(),
          channel_id: String.t(),
          message_id: String.t(),
          guild_id: String.t() | nil,
          emoji: Emoji.t(),
          member: Member.t() | nil,
          message_author_id: String.t() | nil,
          burst: boolean(),
          burst_colors: [String.t()],
          type: integer()
        }

  defstruct [
    :user_id,
    :channel_id,
    :message_id,
    :guild_id,
    :emoji,
    :member,
    :message_author_id,
    burst: false,
    burst_colors: [],
    type: 0
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      user_id: data["user_id"],
      channel_id: data["channel_id"],
      message_id: data["message_id"],
      guild_id: data["guild_id"],
      emoji: Emoji.new(data["emoji"]),
      member: data["member"] && Member.new(Parse.put_guild_id(data["member"], data["guild_id"])),
      message_author_id: data["message_author_id"],
      burst: data["burst"] || false,
      burst_colors: data["burst_colors"] || [],
      type: data["type"] || 0
    }
  end
end
