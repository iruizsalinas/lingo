defmodule Lingo.Type.Webhook do
  @moduledoc false

  alias Lingo.Type.{Channel, Guild, User}

  @type webhook_type :: :incoming | :channel_follower | :application

  @type t :: %__MODULE__{
          id: String.t(),
          type: webhook_type(),
          guild_id: String.t() | nil,
          channel_id: String.t() | nil,
          user: User.t() | nil,
          name: String.t() | nil,
          avatar: String.t() | nil,
          token: String.t() | nil,
          application_id: String.t() | nil,
          source_guild: Guild.t() | nil,
          source_channel: Channel.t() | nil,
          url: String.t() | nil
        }

  defstruct [
    :id,
    :type,
    :guild_id,
    :channel_id,
    :user,
    :name,
    :avatar,
    :token,
    :application_id,
    :source_guild,
    :source_channel,
    :url
  ]

  @webhook_types %{1 => :incoming, 2 => :channel_follower, 3 => :application}

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      type: Map.get(@webhook_types, data["type"], data["type"]),
      guild_id: data["guild_id"],
      channel_id: data["channel_id"],
      user: User.new(data["user"]),
      name: data["name"],
      avatar: data["avatar"],
      token: data["token"],
      application_id: data["application_id"],
      source_guild: Guild.new(data["source_guild"]),
      source_channel: Channel.new(data["source_channel"]),
      url: data["url"]
    }
  end
end
