defmodule Lingo.Type.ScheduledEvent do
  @moduledoc false

  alias Lingo.Type.User

  @type privacy_level :: :guild_only
  @type entity_type :: :stage_instance | :voice | :external
  @type status :: :scheduled | :active | :completed | :canceled

  @type t :: %__MODULE__{
          id: String.t(),
          guild_id: String.t(),
          channel_id: String.t() | nil,
          creator_id: String.t() | nil,
          name: String.t(),
          description: String.t() | nil,
          scheduled_start_time: String.t(),
          scheduled_end_time: String.t() | nil,
          privacy_level: privacy_level(),
          status: status(),
          entity_type: entity_type(),
          entity_id: String.t() | nil,
          entity_metadata: map() | nil,
          creator: User.t() | nil,
          user_count: integer() | nil,
          image: String.t() | nil
        }

  defstruct [
    :id,
    :guild_id,
    :channel_id,
    :creator_id,
    :name,
    :description,
    :scheduled_start_time,
    :scheduled_end_time,
    :entity_id,
    :entity_metadata,
    :creator,
    :user_count,
    :image,
    privacy_level: :guild_only,
    status: :scheduled,
    entity_type: :external
  ]

  @entity_types %{1 => :stage_instance, 2 => :voice, 3 => :external}
  @statuses %{1 => :scheduled, 2 => :active, 3 => :completed, 4 => :canceled}

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      guild_id: data["guild_id"],
      channel_id: data["channel_id"],
      creator_id: data["creator_id"],
      name: data["name"],
      description: data["description"],
      scheduled_start_time: data["scheduled_start_time"],
      scheduled_end_time: data["scheduled_end_time"],
      privacy_level: :guild_only,
      status: Map.get(@statuses, data["status"], :scheduled),
      entity_type: Map.get(@entity_types, data["entity_type"], :external),
      entity_id: data["entity_id"],
      entity_metadata: data["entity_metadata"],
      creator: User.new(data["creator"]),
      user_count: data["user_count"],
      image: data["image"]
    }
  end
end
