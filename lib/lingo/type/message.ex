defmodule Lingo.Type.Message do
  @moduledoc """
  A message.

  `type` is an atom such as `:default` or `:reply`, or Discord's number for
  types Lingo doesn't know yet. `timestamp` and `edited_timestamp` are
  `DateTime`s.
  """

  alias Lingo.Type.{
    Application,
    Attachment,
    Channel,
    Codes,
    Embed,
    Member,
    Parse,
    Poll,
    Reaction,
    Sticker,
    User
  }

  @type message_type :: atom() | integer()

  @type t :: %__MODULE__{
          id: String.t(),
          channel_id: String.t(),
          channel_type: Channel.channel_type() | integer() | nil,
          guild_id: String.t() | nil,
          author: User.t(),
          member: Member.t() | nil,
          content: String.t(),
          timestamp: DateTime.t(),
          edited_timestamp: DateTime.t() | nil,
          tts: boolean(),
          mention_everyone: boolean(),
          mentions: [User.t()],
          mention_members: %{optional(String.t()) => Member.t()},
          mention_roles: [String.t()],
          mention_channels: [map()],
          attachments: [Attachment.t()],
          embeds: [Embed.t()],
          reactions: [Reaction.t()],
          nonce: String.t() | integer() | nil,
          pinned: boolean(),
          webhook_id: String.t() | nil,
          type: message_type(),
          activity: map() | nil,
          application: Application.t() | nil,
          application_id: String.t() | nil,
          flags: integer(),
          message_reference: map() | nil,
          message_snapshots: [map()],
          referenced_message: t() | nil,
          interaction_metadata: map() | nil,
          interaction: map() | nil,
          thread: Channel.t() | nil,
          components: [map()],
          sticker_items: [map()],
          stickers: [Sticker.t()],
          position: integer() | nil,
          role_subscription_data: map() | nil,
          resolved: map() | nil,
          poll: Poll.t() | nil,
          call: map() | nil,
          shared_client_theme: map() | nil
        }

  defstruct [
    :id,
    :channel_id,
    :channel_type,
    :guild_id,
    :author,
    :member,
    :timestamp,
    :edited_timestamp,
    :webhook_id,
    :referenced_message,
    :nonce,
    :activity,
    :application,
    :application_id,
    :message_reference,
    :interaction_metadata,
    :interaction,
    :thread,
    :position,
    :role_subscription_data,
    :resolved,
    :poll,
    :call,
    :shared_client_theme,
    content: "",
    type: :default,
    tts: false,
    mention_everyone: false,
    mentions: [],
    mention_members: %{},
    mention_roles: [],
    mention_channels: [],
    attachments: [],
    embeds: [],
    reactions: [],
    pinned: false,
    flags: 0,
    components: [],
    sticker_items: [],
    stickers: [],
    message_snapshots: []
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    mentions = data["mentions"] || []

    struct(Parse.fields(__MODULE__, data),
      channel_type: Codes.name(:channel_type, data["channel_type"]),
      author: User.new(data["author"]),
      member: author_member(data["member"], data["guild_id"], data["author"]),
      timestamp: Parse.timestamp(data["timestamp"]),
      edited_timestamp: Parse.timestamp(data["edited_timestamp"]),
      mentions: Enum.map(mentions, &User.new/1),
      mention_members: mention_members(mentions, data["guild_id"]),
      attachments: Parse.list(data["attachments"], &Attachment.new/1),
      embeds: Parse.list(data["embeds"], &Embed.new/1),
      reactions: Parse.list(data["reactions"], &Reaction.new/1),
      type: Codes.name(:message_type, data["type"], :default),
      referenced_message: new(data["referenced_message"]),
      thread: Channel.new(data["thread"]),
      application: Application.new(data["application"]),
      stickers: Parse.list(data["stickers"], &Sticker.new/1),
      poll: Poll.new(data["poll"]),
      message_snapshots: Parse.list(data["message_snapshots"], &snapshot/1)
    )
  end

  defp snapshot(%{"message" => message} = snapshot),
    do: Map.put(snapshot, "message", new(message))

  defp snapshot(snapshot), do: snapshot

  defp author_member(nil, _guild_id, _author), do: nil

  defp author_member(data, guild_id, author) when is_map(data) do
    data = if author, do: Map.put_new(data, "user", author), else: data
    data |> Parse.put_guild_id(guild_id) |> Member.new()
  end

  defp mention_members(mentions, guild_id) do
    for %{"id" => user_id, "member" => member} = mention <- mentions, is_map(member), into: %{} do
      user = Map.delete(mention, "member")
      {user_id, member |> Parse.put_guild_id(guild_id) |> Map.put("user", user) |> Member.new()}
    end
  end
end
