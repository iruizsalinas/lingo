defmodule Lingo.Api.Invite do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Invite

  def get(invite_code, opts \\ []) do
    params =
      opts
      |> Keyword.take([:with_counts, :with_expiration, :guild_scheduled_event_id])
      |> Enum.into(%{})

    with {:ok, data} <- Client.request(:get, "/invites/#{invite_code}", params: params) do
      {:ok, Invite.new(data)}
    end
  end

  def delete(invite_code, opts \\ []) do
    with {:ok, data} <- Client.request(:delete, "/invites/#{invite_code}", reason: opts[:reason]) do
      {:ok, Invite.new(data)}
    end
  end

  def get_target_users(invite_code) do
    with {:ok, body} when is_binary(body) <-
           Client.request(:get, "/invites/#{invite_code}/target-users") do
      ids =
        body
        |> String.split(~r/\r?\n/, trim: true)
        |> Enum.drop(1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:ok, ids}
    end
  end

  def set_target_users(invite_code, user_ids) when is_list(user_ids) do
    csv = "user_id\n" <> Enum.join(user_ids, "\n")

    multipart = [
      {"target_users_file", {csv, filename: "target_users.csv", content_type: "text/csv"}}
    ]

    Client.request(:put, "/invites/#{invite_code}/target-users", multipart: multipart)
  end

  def get_target_users_status(invite_code) do
    Client.request(:get, "/invites/#{invite_code}/target-users/job-status")
  end
end
