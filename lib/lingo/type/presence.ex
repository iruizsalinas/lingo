defmodule Lingo.Type.Presence do
  @moduledoc "A member's status and activities."

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

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      user: User.new(data["user"]),
      guild_id: data["guild_id"],
      status: Map.get(@statuses, data["status"], data["status"] || :offline),
      activities: (data["activities"] || []) |> Enum.map(&Lingo.Type.Activity.new/1),
      client_status: data["client_status"]
    }
  end
end
