defmodule Lingo.Type.CommandPermissions do
  @moduledoc """
  The permissions of one command in a guild: which roles, users and channels
  may use it.

  When `id` is the application's id, they apply to every command without
  permissions of its own. Each permission's `type` is `:role`, `:user` or
  `:channel`, and `permission` whether it's allowed.
  """

  @type permission :: %{
          id: String.t(),
          type: :role | :user | :channel | integer(),
          permission: boolean()
        }
  @type t :: %__MODULE__{
          id: String.t(),
          application_id: String.t(),
          guild_id: String.t(),
          permissions: [permission()]
        }

  defstruct [:id, :application_id, :guild_id, permissions: []]

  @types %{1 => :role, 2 => :user, 3 => :channel}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      application_id: data["application_id"],
      guild_id: data["guild_id"],
      permissions: Enum.map(data["permissions"] || [], &permission/1)
    }
  end

  defp permission(data) do
    %{
      id: data["id"],
      type: Map.get(@types, data["type"], data["type"]),
      permission: data["permission"]
    }
  end
end
