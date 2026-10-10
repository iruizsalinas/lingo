defmodule Lingo.Api.Invite do
  @moduledoc """
  Invites, including restricting them to target users.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.Invite

  @doc "Fetches an invite by code."
  @spec get(String.t(), keyword()) :: Api.result(Invite.t())
  def get(invite_code, opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/invites/#{invite_code}", params: params) |> Client.into(&Invite.new/1)
  end

  @doc "Deletes an invite."
  @spec delete(String.t(), keyword()) :: Api.result(Invite.t())
  def delete(invite_code, opts \\ []) do
    Client.request(:delete, "/invites/#{invite_code}", reason: opts[:reason])
    |> Client.into(&Invite.new/1)
  end

  @doc "Fetches the users an invite is restricted to."
  @spec list_target_users(String.t()) :: Api.result([Api.id()])
  def list_target_users(invite_code) do
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

  @doc "Restricts an invite to the given users."
  @spec set_target_users(String.t(), [Api.id()]) :: Api.result()
  def set_target_users(invite_code, user_ids) when is_list(user_ids) do
    csv = "user_id\n" <> Enum.join(user_ids, "\n")

    multipart = [
      {"target_users_file", {csv, filename: "target_users.csv", content_type: "text/csv"}}
    ]

    Client.request(:put, "/invites/#{invite_code}/target-users", multipart: multipart)
  end

  @doc "Adds a user to an invite's allowed users."
  @spec add_target_user(String.t(), Api.id()) :: Api.result()
  def add_target_user(invite_code, user_id) do
    Client.request(:put, "/invites/#{invite_code}/target-users/#{user_id}")
  end

  @doc "Removes a user from an invite's allowed users."
  @spec remove_target_user(String.t(), Api.id()) :: Api.result()
  def remove_target_user(invite_code, user_id) do
    Client.request(:delete, "/invites/#{invite_code}/target-users/#{user_id}")
  end

  @doc "Adds several users to an invite's allowed users."
  @spec bulk_add_target_users(String.t(), [Api.id()]) :: Api.result() | {:ok, map()}
  def bulk_add_target_users(invite_code, user_ids) when is_list(user_ids) do
    Client.request(:post, "/invites/#{invite_code}/target-users/bulk-add",
      json: %{user_ids: user_ids}
    )
  end

  @doc "Removes several users from an invite's allowed users."
  @spec bulk_delete_target_users(String.t(), [Api.id()]) :: Api.result() | {:ok, map()}
  def bulk_delete_target_users(invite_code, user_ids) when is_list(user_ids) do
    Client.request(:post, "/invites/#{invite_code}/target-users/bulk-delete",
      json: %{user_ids: user_ids}
    )
  end

  @doc "Fetches the status of an invite's pending target user changes."
  @spec get_target_users_status(String.t()) :: Api.result(map())
  def get_target_users_status(invite_code) do
    Client.request(:get, "/invites/#{invite_code}/target-users/job-status")
  end

  @doc "Lists a channel's invites."
  @spec list_channel(Api.id()) :: Api.result([Invite.t()])
  def list_channel(channel_id) do
    Client.request(:get, "/channels/#{channel_id}/invites") |> Client.into(&Invite.new/1)
  end

  @doc """
  Creates an invite to a channel. `:target_users_file` limits who can use
  it: a list of user ids, a CSV string, or `{filename, csv}`.
  """
  @spec create(Api.id(), Api.params(), keyword()) :: Api.result(Invite.t())
  def create(channel_id, params \\ %{}, opts \\ []) do
    request_opts = [reason: opts[:reason]] ++ body(Map.new(params))

    Client.request(:post, "/channels/#{channel_id}/invites", request_opts)
    |> Client.into(&Invite.new/1)
  end

  # a target users file goes up as CSV next to the JSON payload
  defp body(params) do
    {file, params} = Map.pop(params, :target_users_file)
    {file, json} = if file, do: {file, params}, else: Map.pop(params, "target_users_file")

    if file do
      payload = {"payload_json", {JSON.encode!(json), content_type: "application/json"}}
      [multipart: [payload, users_file(file)]]
    else
      [json: json]
    end
  end

  defp users_file(user_ids) when is_list(user_ids),
    do: users_file("user_id\n" <> Enum.join(user_ids, "\n"))

  defp users_file({filename, csv}) when is_binary(filename),
    do: {"target_users_file", {csv, filename: filename, content_type: "text/csv"}}

  defp users_file(csv) when is_binary(csv),
    do: {"target_users_file", {csv, filename: "target_users.csv", content_type: "text/csv"}}

  @doc "Lists a guild's invites."
  @spec list_guild(Api.id()) :: Api.result([Invite.t()])
  def list_guild(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/invites") |> Client.into(&Invite.new/1)
  end
end
