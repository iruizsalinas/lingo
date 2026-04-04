defmodule Lingo.Api.Application do
  @moduledoc false

  alias Lingo.Api.Client

  def get_current do
    Client.request(:get, "/applications/@me")
  end

  def modify_current(params) do
    Client.request(:patch, "/applications/@me", json: params)
  end

  def get_role_connection_metadata(application_id) do
    Client.request(:get, "/applications/#{application_id}/role-connections/metadata")
  end

  def update_role_connection_metadata(application_id, params) do
    Client.request(:put, "/applications/#{application_id}/role-connections/metadata",
      json: params
    )
  end
end
