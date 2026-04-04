defmodule Lingo.Api.StageInstance do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.StageInstance

  def create(params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:post, "/stage-instances", json: params, reason: opts[:reason]) do
      {:ok, StageInstance.new(data)}
    end
  end

  def get(channel_id) do
    with {:ok, data} <- Client.request(:get, "/stage-instances/#{channel_id}") do
      {:ok, StageInstance.new(data)}
    end
  end

  def modify(channel_id, params, opts \\ []) do
    with {:ok, data} <-
           Client.request(:patch, "/stage-instances/#{channel_id}",
             json: params,
             reason: opts[:reason]
           ) do
      {:ok, StageInstance.new(data)}
    end
  end

  def delete(channel_id, opts \\ []) do
    Client.request(:delete, "/stage-instances/#{channel_id}", reason: opts[:reason])
  end
end
