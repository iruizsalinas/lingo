defmodule Lingo.Type.ActivityInstance do
  @moduledoc """
  A running instance of the app's Activity, from
  `Lingo.Api.Application.get_activity_instance/1`. `users` are the ids of
  the users in it; `location` says where it runs, with `kind`
  `:guild_channel` or `:private_channel` (a DM or group DM).
  """

  @type location :: %{
          id: String.t(),
          kind: :guild_channel | :private_channel | String.t(),
          channel_id: String.t(),
          guild_id: String.t() | nil
        }
  @type t :: %__MODULE__{
          application_id: String.t(),
          instance_id: String.t(),
          launch_id: String.t(),
          location: location() | nil,
          users: [String.t()]
        }

  defstruct [:application_id, :instance_id, :launch_id, :location, users: []]

  @kinds %{"gc" => :guild_channel, "pc" => :private_channel}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      application_id: data["application_id"],
      instance_id: data["instance_id"],
      launch_id: data["launch_id"],
      location: location(data["location"]),
      users: data["users"] || []
    }
  end

  defp location(nil), do: nil

  defp location(data) do
    %{
      id: data["id"],
      kind: Map.get(@kinds, data["kind"], data["kind"]),
      channel_id: data["channel_id"],
      guild_id: data["guild_id"]
    }
  end
end
