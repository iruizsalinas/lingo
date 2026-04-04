defmodule Lingo.Type.Message do
  @moduledoc false

  alias Lingo.Type.{Embed, Member, User}

  @type t :: %__MODULE__{
          id: String.t(),
          channel_id: String.t(),
          guild_id: String.t() | nil,
          author: User.t(),
          member: Member.t() | nil,
          content: String.t(),
          timestamp: String.t(),
          edited_timestamp: String.t() | nil,
          tts: boolean(),
          mention_everyone: boolean(),
          mentions: [User.t()],
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
          referenced_message: t() | nil,
          interaction_metadata: map() | nil,
          thread: Lingo.Type.Channel.t() | nil,
          components: [map()],
          sticker_items: [map()],
          message_snapshots: [map()],
          position: integer() | nil
        }

  defstruct [
    :id,
    :channel_id,
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
    :thread,
    :position,
    type: 0,
    tts: false,
    mention_everyone: false,
    mentions: [],
    mention_roles: [],
    mention_channels: [],
    attachments: [],
    embeds: [],
    reactions: [],
    pinned: false,
    flags: 0,
    components: [],
    sticker_items: [],
    message_snapshots: []
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      channel_id: data["channel_id"],
      guild_id: data["guild_id"],
      author: User.new(data["author"]),
      member: Member.new(data["member"]),
      content: data["content"] || "",
      timestamp: data["timestamp"],
      edited_timestamp: data["edited_timestamp"],
      tts: data["tts"] || false,
      mention_everyone: data["mention_everyone"] || false,
      mentions: (data["mentions"] || []) |> Enum.map(&User.new/1),
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
      thread: if(data["thread"], do: Lingo.Type.Channel.new(data["thread"])),
      components: data["components"] || [],
      sticker_items: data["sticker_items"] || [],
      message_snapshots: parse_snapshots(data["message_snapshots"]),
      position: data["position"]
    }
  end

  defp parse_snapshots(nil), do: []

  defp parse_snapshots(snapshots) when is_list(snapshots) do
    Enum.map(snapshots, fn %{"message" => msg} -> %{message: new(msg)} end)
  end
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
