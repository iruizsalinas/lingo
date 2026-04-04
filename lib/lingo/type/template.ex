defmodule Lingo.Type.GuildTemplate do
  @moduledoc false

  alias Lingo.Type.{Guild, User}

  @type t :: %__MODULE__{
          code: String.t(),
          name: String.t(),
          description: String.t() | nil,
          usage_count: integer(),
          creator_id: String.t(),
          creator: User.t() | nil,
          created_at: String.t(),
          updated_at: String.t(),
          source_guild_id: String.t(),
          serialized_source_guild: Guild.t() | nil,
          is_dirty: boolean() | nil
        }

  defstruct [
    :code,
    :name,
    :description,
    :creator_id,
    :creator,
    :created_at,
    :updated_at,
    :source_guild_id,
    :serialized_source_guild,
    :is_dirty,
    usage_count: 0
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      code: data["code"],
      name: data["name"],
      description: data["description"],
      usage_count: data["usage_count"] || 0,
      creator_id: data["creator_id"],
      creator: User.new(data["creator"]),
      created_at: data["created_at"],
      updated_at: data["updated_at"],
      source_guild_id: data["source_guild_id"],
      serialized_source_guild: Guild.new(data["serialized_source_guild"]),
      is_dirty: data["is_dirty"]
    }
  end
end
