defmodule Lingo.Api.User do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.{Channel, User}

  def get_current do
    with {:ok, data} <- Client.request(:get, "/users/@me") do
      {:ok, User.new(data)}
    end
  end

  def get(user_id) do
    with {:ok, data} <- Client.request(:get, "/users/#{user_id}") do
      {:ok, User.new(data)}
    end
  end

  def modify_current(params) do
    with {:ok, data} <- Client.request(:patch, "/users/@me", json: params) do
      {:ok, User.new(data)}
    end
  end

  def get_guilds(opts \\ []) do
    params =
      opts
      |> Keyword.take([:before, :after, :limit, :with_counts])
      |> Enum.into(%{})

    Client.request(:get, "/users/@me/guilds", params: params)
  end

  def leave_guild(guild_id) do
    Client.request(:delete, "/users/@me/guilds/#{guild_id}")
  end

  def create_dm(recipient_id) do
    with {:ok, data} <-
           Client.request(:post, "/users/@me/channels", json: %{recipient_id: recipient_id}) do
      {:ok, Channel.new(data)}
    end
  end
end
