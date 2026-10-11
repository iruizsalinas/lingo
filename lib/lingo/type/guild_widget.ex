defmodule Lingo.Type.GuildWidget do
  @moduledoc """
  A guild's public widget, from `Lingo.Api.Guild.get_widget/1`: the voice
  and stage channels open to @everyone, and up to 100 online members.

  Members are maps with atom keys and `status` `:online`, `:idle` or `:dnd`;
  their `id`, `discriminator` and `avatar` are anonymized by Discord.
  """

  alias Lingo.Type.{Channel, Parse}

  @type member :: %{
          id: String.t(),
          username: String.t(),
          discriminator: String.t(),
          avatar: String.t() | nil,
          status: :online | :idle | :dnd | String.t() | nil,
          avatar_url: String.t() | nil
        }
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          instant_invite: String.t() | nil,
          channels: [Channel.t()],
          members: [member()],
          presence_count: integer()
        }

  defstruct [:id, :name, :instant_invite, channels: [], members: [], presence_count: 0]

  @statuses %{"online" => :online, "idle" => :idle, "dnd" => :dnd}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      name: data["name"],
      instant_invite: data["instant_invite"],
      channels: Parse.list(data["channels"], &Channel.new(Parse.put_guild_id(&1, data["id"]))),
      members: Parse.list(data["members"], &member/1),
      presence_count: data["presence_count"] || 0
    }
  end

  defp member(data) do
    %{
      id: data["id"],
      username: data["username"],
      discriminator: data["discriminator"],
      avatar: data["avatar"],
      status: Map.get(@statuses, data["status"], data["status"]),
      avatar_url: data["avatar_url"]
    }
  end
end
