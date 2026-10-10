defmodule Lingo.Api.StageInstance do
  @moduledoc """
  Stage instances: live stages in stage channels.

  Every function returns `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`. Calls go to the current bot (see `Lingo.with_bot/2`).
  """

  alias Lingo.Api
  alias Lingo.Rest.Client
  alias Lingo.Type.StageInstance

  @doc "Starts a stage instance in a stage channel."
  @spec create(Api.params(), keyword()) :: Api.result(StageInstance.t())
  def create(params, opts \\ []) do
    Client.request(:post, "/stage-instances", json: params, reason: opts[:reason])
    |> Client.into(&StageInstance.new/1)
  end

  @doc "Fetches the stage instance of a stage channel."
  @spec get(Api.id()) :: Api.result(StageInstance.t())
  def get(channel_id) do
    Client.request(:get, "/stage-instances/#{channel_id}") |> Client.into(&StageInstance.new/1)
  end

  @doc "Edits a stage instance."
  @spec update(Api.id(), Api.params(), keyword()) :: Api.result(StageInstance.t())
  def update(channel_id, params, opts \\ []) do
    Client.request(:patch, "/stage-instances/#{channel_id}",
      json: params,
      reason: opts[:reason]
    )
    |> Client.into(&StageInstance.new/1)
  end

  @doc "Ends a stage instance."
  @spec delete(Api.id(), keyword()) :: Api.result()
  def delete(channel_id, opts \\ []) do
    Client.request(:delete, "/stage-instances/#{channel_id}", reason: opts[:reason])
  end
end
