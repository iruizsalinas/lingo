defmodule Lingo.Api.User do
  @moduledoc """
  Users, the bot's own user, its guilds and DMs.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.{Channel, User}

  @doc "Fetches the bot's user."
  @spec get_current() :: Api.result(User.t())
  def get_current do
    Client.request(:get, "/users/@me") |> Client.into(&User.new/1)
  end

  @doc "Fetches a user."
  @spec get(Api.id()) :: Api.result(User.t())
  def get(user_id) do
    Client.request(:get, "/users/#{user_id}") |> Client.into(&User.new/1)
  end

  @doc "Edits the bot's username, avatar or banner."
  @spec update_current(Api.params()) :: Api.result(User.t())
  def update_current(params) do
    Client.request(:patch, "/users/@me", json: params) |> Client.into(&User.new/1)
  end

  @doc "Lists the guilds the bot is in, 200 at a time."
  @spec list_guilds(keyword()) :: Api.result([map()])
  def list_guilds(opts \\ []) do
    params =
      Client.params(opts)

    Client.request(:get, "/users/@me/guilds", params: params)
  end

  @doc "Makes the bot leave a guild."
  @spec leave_guild(Api.id()) :: Api.result()
  def leave_guild(guild_id) do
    Client.request(:delete, "/users/@me/guilds/#{guild_id}")
  end

  @doc "Opens a DM channel with a user. Send to it with `Lingo.Api.Message.create/2`."
  @spec create_dm(Api.id()) :: Api.result(Channel.t())
  def create_dm(recipient_id) do
    Client.request(:post, "/users/@me/channels", json: %{recipient_id: recipient_id})
    |> Client.into(&Channel.new/1)
  end
end
