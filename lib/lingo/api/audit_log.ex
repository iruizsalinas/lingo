defmodule Lingo.Api.AuditLog do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.AuditLog

  def get(guild_id, opts \\ []) do
    params =
      opts
      |> Keyword.take([:user_id, :action_type, :before, :after, :limit])
      |> Enum.into(%{})

    with {:ok, data} <- Client.request(:get, "/guilds/#{guild_id}/audit-logs", params: params) do
      {:ok, AuditLog.new(data)}
    end
  end
end
