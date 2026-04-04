defmodule Lingo.Type.Presence do
  @moduledoc false

  alias Lingo.Type.User

  @type status :: :online | :idle | :dnd | :offline

  @type t :: %__MODULE__{
          user: User.t() | nil,
          guild_id: String.t() | nil,
          status: status(),
          activities: [Lingo.Type.Activity.t()],
          client_status: map() | nil
        }

  defstruct [:user, :guild_id, :client_status, status: :offline, activities: []]

  @statuses %{
    "online" => :online,
    "idle" => :idle,
    "dnd" => :dnd,
    "offline" => :offline,
    "invisible" => :offline
  }

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      user: User.new(data["user"]),
      guild_id: data["guild_id"],
      status: Map.get(@statuses, data["status"], :offline),
      activities: (data["activities"] || []) |> Enum.map(&Lingo.Type.Activity.new/1),
      client_status: data["client_status"]
    }
  end
end

defmodule Lingo.Type.Activity do
  @moduledoc false

  @type activity_type :: :playing | :streaming | :listening | :watching | :custom | :competing

  @type t :: %__MODULE__{
          name: String.t(),
          type: activity_type(),
          url: String.t() | nil,
          created_at: integer() | nil,
          application_id: String.t() | nil,
          details: String.t() | nil,
          state: String.t() | nil
        }

  defstruct [:name, :url, :created_at, :application_id, :details, :state, type: :playing]

  @activity_types %{
    0 => :playing,
    1 => :streaming,
    2 => :listening,
    3 => :watching,
    4 => :custom,
    5 => :competing
  }

  @activity_types_reverse Map.new(@activity_types, fn {k, v} -> {v, k} end)

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      name: data["name"],
      type: Map.get(@activity_types, data["type"], :playing),
      url: data["url"],
      created_at: data["created_at"],
      application_id: data["application_id"],
      details: data["details"],
      state: data["state"]
    }
  end

  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = a) do
    %{"name" => a.name, "type" => Map.get(@activity_types_reverse, a.type, 0)}
    |> then(fn m -> if a.url, do: Map.put(m, "url", a.url), else: m end)
  end
end
