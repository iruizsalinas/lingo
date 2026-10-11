defmodule Lingo.Api.Invite do
  @moduledoc """
  Invites, including restricting them to target users.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Api.Invite.TargetUsers
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
           Client.request(:get, "/invites/#{invite_code}/target-users"),
         do: {:ok, TargetUsers.ids(body)}
  end

  @doc "Restricts an invite to the given users."
  @spec set_target_users(String.t(), [Api.id()]) :: Api.result()
  def set_target_users(invite_code, user_ids) when is_list(user_ids) do
    Client.request(:put, "/invites/#{invite_code}/target-users",
      multipart: [TargetUsers.file(user_ids)]
    )
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

  @doc "Adds up to 1000 users to an invite's allowed users."
  @spec bulk_add_target_users(String.t(), [Api.id()]) :: Api.result()
  def bulk_add_target_users(invite_code, user_ids) when is_list(user_ids) do
    Client.request(:post, "/invites/#{invite_code}/target-users/bulk-add",
      json: %{user_ids: user_ids}
    )
  end

  @doc "Removes up to 1000 users from an invite's allowed users."
  @spec bulk_delete_target_users(String.t(), [Api.id()]) :: Api.result()
  def bulk_delete_target_users(invite_code, user_ids) when is_list(user_ids) do
    Client.request(:post, "/invites/#{invite_code}/target-users/bulk-delete",
      json: %{user_ids: user_ids}
    )
  end

  @typedoc """
  The progress of processing an invite's target users file. `status` is
  `:unspecified`, `:processing`, `:completed` or `:failed` (see
  `error_message`).
  """
  @type target_users_job :: %{
          status: :unspecified | :processing | :completed | :failed | integer(),
          total_users: non_neg_integer(),
          processed_users: non_neg_integer(),
          created_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          error_message: String.t() | nil
        }

  @doc "Fetches the progress of processing an invite's target users file."
  @spec get_target_users_status(String.t()) :: Api.result(target_users_job())
  def get_target_users_status(invite_code) do
    Client.request(:get, "/invites/#{invite_code}/target-users/job-status")
    |> Client.into(&TargetUsers.job/1)
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
    request_opts = [reason: opts[:reason]] ++ TargetUsers.invite_body(Map.new(params))

    Client.request(:post, "/channels/#{channel_id}/invites", request_opts)
    |> Client.into(&Invite.new/1)
  end

  @doc "Lists a guild's invites."
  @spec list_guild(Api.id()) :: Api.result([Invite.t()])
  def list_guild(guild_id) do
    Client.request(:get, "/guilds/#{guild_id}/invites") |> Client.into(&Invite.new/1)
  end
end
