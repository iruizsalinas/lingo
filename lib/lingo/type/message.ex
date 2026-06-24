defmodule Lingo.Type.Message do
  @moduledoc false

  alias Lingo.Type.{Embed, Member, User}

  @type t :: %__MODULE__{
          id: String.t(),
          channel_id: String.t(),
          channel_type: integer() | nil,
          guild_id: String.t() | nil,
          author: User.t(),
          member: Member.t() | nil,
          content: String.t(),
          timestamp: String.t(),
          edited_timestamp: String.t() | nil,
          tts: boolean(),
          mention_everyone: boolean(),
          mentions: [User.t()],
          mention_members: %{optional(String.t()) => Member.t()},
          mention_roles: [String.t()],
          mention_channels: [map()],
          attachments: [Lingo.Type.Attachment.t()],
          embeds: [Embed.t()],
          reactions: [Lingo.Type.Reaction.t()],
          nonce: String.t() | integer() | nil,
          pinned: boolean(),
          webhook_id: String.t() | nil,
          type: integer(),
          activity: map() | nil,
          application: map() | nil,
          application_id: String.t() | nil,
          flags: integer(),
          message_reference: map() | nil,
          message_snapshots: [map()],
          referenced_message: t() | nil,
          interaction_metadata: map() | nil,
          interaction: map() | nil,
          thread: Lingo.Type.Channel.t() | nil,
          components: [map()],
          sticker_items: [map()],
          stickers: [map()],
          position: integer() | nil,
          role_subscription_data: map() | nil,
          resolved: map() | nil,
          poll: map() | nil,
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
    :content,
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
    type: 0,
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

  def new(nil), do: nil

  def new(data) when is_map(data) do
    mentions = data["mentions"] || []

    %__MODULE__{
      id: data["id"],
      channel_id: data["channel_id"],
      channel_type: data["channel_type"],
      guild_id: data["guild_id"],
      author: User.new(data["author"]),
      member: parse_author_member(data["member"], data["guild_id"], data["author"]),
      content: data["content"] || "",
      timestamp: data["timestamp"],
      edited_timestamp: data["edited_timestamp"],
      tts: data["tts"] || false,
      mention_everyone: data["mention_everyone"] || false,
      mentions: Enum.map(mentions, &User.new/1),
      mention_members: parse_mention_members(mentions, data["guild_id"]),
      mention_roles: data["mention_roles"] || [],
      mention_channels: data["mention_channels"] || [],
      attachments: (data["attachments"] || []) |> Enum.map(&Lingo.Type.Attachment.new/1),
      embeds: (data["embeds"] || []) |> Enum.map(&Embed.new/1),
      reactions: (data["reactions"] || []) |> Enum.map(&Lingo.Type.Reaction.new/1),
      nonce: data["nonce"],
      pinned: data["pinned"] || false,
      webhook_id: data["webhook_id"],
      type: data["type"] || 0,
      activity: data["activity"],
      application: data["application"],
      application_id: data["application_id"],
      flags: data["flags"] || 0,
      message_reference: data["message_reference"],
      referenced_message: new(data["referenced_message"]),
      interaction_metadata: data["interaction_metadata"],
      interaction: data["interaction"],
      thread: if(data["thread"], do: Lingo.Type.Channel.new(data["thread"])),
      components: data["components"] || [],
      sticker_items: data["sticker_items"] || [],
      stickers: data["stickers"] || [],
      message_snapshots: parse_snapshots(data["message_snapshots"]),
      position: data["position"],
      role_subscription_data: data["role_subscription_data"],
      resolved: data["resolved"],
      poll: data["poll"],
      call: data["call"],
      shared_client_theme: data["shared_client_theme"]
    }
  end

  defp parse_snapshots(nil), do: []

  defp parse_snapshots(snapshots) when is_list(snapshots) do
    Enum.map(snapshots, fn
      %{"message" => msg} = snapshot -> Map.put(snapshot, "message", new(msg))
      snapshot -> snapshot
    end)
  end

  defp parse_author_member(nil, _guild_id, _author), do: nil

  defp parse_author_member(member_data, guild_id, author) when is_map(member_data) do
    member_data
    |> maybe_put_guild_id(guild_id)
    |> maybe_put_user(author)
    |> Member.new()
  end

  defp parse_mention_members(mentions, guild_id) do
    mentions
    |> Enum.flat_map(fn
      %{"id" => user_id, "member" => member_data} = mention when is_map(member_data) ->
        member =
          member_data
          |> maybe_put_guild_id(guild_id)
          |> Map.put("user", Map.delete(mention, "member"))
          |> Member.new()

        [{user_id, member}]

      _ ->
        []
    end)
    |> Map.new()
  end

  defp maybe_put_user(data, nil), do: data
  defp maybe_put_user(data, author) when is_map(author), do: Map.put_new(data, "user", author)

  defp maybe_put_guild_id(data, nil), do: data
  defp maybe_put_guild_id(data, guild_id), do: Map.put(data, "guild_id", guild_id)
end

defmodule Lingo.Type.Attachment do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          filename: String.t(),
          description: String.t() | nil,
          content_type: String.t() | nil,
          size: integer(),
          url: String.t(),
          proxy_url: String.t(),
          height: integer() | nil,
          width: integer() | nil,
          ephemeral: boolean(),
          duration_secs: float() | nil,
          waveform: String.t() | nil,
          flags: integer()
        }

  defstruct [
    :id,
    :filename,
    :description,
    :content_type,
    :size,
    :url,
    :proxy_url,
    :height,
    :width,
    :duration_secs,
    :waveform,
    ephemeral: false,
    flags: 0
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      filename: data["filename"],
      description: data["description"],
      content_type: data["content_type"],
      size: data["size"],
      url: data["url"],
      proxy_url: data["proxy_url"],
      height: data["height"],
      width: data["width"],
      ephemeral: data["ephemeral"] || false,
      duration_secs: data["duration_secs"],
      waveform: data["waveform"],
      flags: data["flags"] || 0
    }
  end
end

defmodule Lingo.Type.Reaction do
  @moduledoc false

  alias Lingo.Type.Emoji

  @type t :: %__MODULE__{
          count: integer(),
          count_details: map(),
          me: boolean(),
          me_burst: boolean(),
          emoji: Emoji.t(),
          burst_colors: [String.t()]
        }

  defstruct [
    :emoji,
    :count_details,
    count: 0,
    me: false,
    me_burst: false,
    burst_colors: []
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      count: data["count"] || 0,
      count_details: data["count_details"],
      me: data["me"] || false,
      me_burst: data["me_burst"] || false,
      emoji: Emoji.new(data["emoji"]),
      burst_colors: data["burst_colors"] || []
    }
  end
end
