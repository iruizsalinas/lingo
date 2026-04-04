defmodule Lingo.Api.Interaction do
  @moduledoc false

  alias Lingo.Api.Client
  alias Lingo.Type.Message

  @response_types %{
    pong: 1,
    channel_message: 4,
    deferred_channel_message: 5,
    deferred_update_message: 6,
    update_message: 7,
    autocomplete: 8,
    modal: 9
  }

  def create_response(interaction_id, interaction_token, type, data \\ nil, opts \\ []) do
    type_int = Map.get(@response_types, type, type)
    params = if opts[:with_response], do: %{with_response: true}, else: nil

    case data do
      %{files: files} = data_map when is_list(files) ->
        clean_data = Map.delete(data_map, :files)
        json = %{type: type_int, data: clean_data}

        Client.request(
          :post,
          "/interactions/#{interaction_id}/#{interaction_token}/callback",
          multipart: build_multipart(json, files),
          params: params
        )

      nil ->
        Client.request(
          :post,
          "/interactions/#{interaction_id}/#{interaction_token}/callback",
          json: %{type: type_int},
          params: params
        )

      data ->
        Client.request(
          :post,
          "/interactions/#{interaction_id}/#{interaction_token}/callback",
          json: %{type: type_int, data: data},
          params: params
        )
    end
  end

  def get_original_response(application_id, interaction_token) do
    with {:ok, data} <-
           Client.request(
             :get,
             "/webhooks/#{application_id}/#{interaction_token}/messages/@original"
           ) do
      {:ok, Message.new(data)}
    end
  end

  def edit_original_response(application_id, interaction_token, params) when is_map(params) do
    {files, json} = Map.pop(params, :files)

    opts =
      if files do
        [multipart: build_multipart(json, files)]
      else
        [json: json]
      end

    with {:ok, data} <-
           Client.request(
             :patch,
             "/webhooks/#{application_id}/#{interaction_token}/messages/@original",
             opts
           ) do
      {:ok, Message.new(data)}
    end
  end

  def edit_original_response(application_id, interaction_token, params) do
    with {:ok, data} <-
           Client.request(
             :patch,
             "/webhooks/#{application_id}/#{interaction_token}/messages/@original",
             json: params
           ) do
      {:ok, Message.new(data)}
    end
  end

  def delete_original_response(application_id, interaction_token) do
    Client.request(:delete, "/webhooks/#{application_id}/#{interaction_token}/messages/@original")
  end

  def create_followup(application_id, interaction_token, params) when is_map(params) do
    {files, json} = Map.pop(params, :files)

    opts =
      if files do
        [multipart: build_multipart(json, files)]
      else
        [json: json]
      end

    with {:ok, data} <-
           Client.request(:post, "/webhooks/#{application_id}/#{interaction_token}", opts) do
      {:ok, Message.new(data)}
    end
  end

  def create_followup(application_id, interaction_token, params) do
    with {:ok, data} <-
           Client.request(:post, "/webhooks/#{application_id}/#{interaction_token}", json: params) do
      {:ok, Message.new(data)}
    end
  end

  def get_followup(application_id, interaction_token, message_id) do
    with {:ok, data} <-
           Client.request(
             :get,
             "/webhooks/#{application_id}/#{interaction_token}/messages/#{message_id}"
           ) do
      {:ok, Message.new(data)}
    end
  end

  def edit_followup(application_id, interaction_token, message_id, params) when is_map(params) do
    {files, json} = Map.pop(params, :files)

    opts =
      if files do
        [multipart: build_multipart(json, files)]
      else
        [json: json]
      end

    with {:ok, data} <-
           Client.request(
             :patch,
             "/webhooks/#{application_id}/#{interaction_token}/messages/#{message_id}",
             opts
           ) do
      {:ok, Message.new(data)}
    end
  end

  def edit_followup(application_id, interaction_token, message_id, params) do
    with {:ok, data} <-
           Client.request(
             :patch,
             "/webhooks/#{application_id}/#{interaction_token}/messages/#{message_id}",
             json: params
           ) do
      {:ok, Message.new(data)}
    end
  end

  def delete_followup(application_id, interaction_token, message_id) do
    Client.request(
      :delete,
      "/webhooks/#{application_id}/#{interaction_token}/messages/#{message_id}"
    )
  end

  defp build_multipart(json, files), do: Client.build_multipart(json, files)
end
