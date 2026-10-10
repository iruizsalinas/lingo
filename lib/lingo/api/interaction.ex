defmodule Lingo.Api.Interaction do
  @moduledoc """
  Interaction responses and follow-ups.

  Inside a bot, `Lingo.Context` answers interactions for you; these are for
  answering them by hand, with the interaction's id and token.
  """

  alias Lingo.Api
  alias Lingo.Rest.{Body, Client}
  alias Lingo.Type.Message

  @response_types %{
    pong: 1,
    channel_message: 4,
    deferred_channel_message: 5,
    deferred_update_message: 6,
    update_message: 7,
    autocomplete: 8,
    modal: 9,
    launch_activity: 12
  }

  @doc """
  Responds to an interaction. `type` is one of `:channel_message`,
  `:deferred_channel_message`, `:deferred_update_message`, `:update_message`,
  `:autocomplete`, `:modal`, `:launch_activity` or `:pong`.
  """
  @spec create_response(Api.id(), String.t(), atom(), map() | nil, keyword()) ::
          Api.result() | {:ok, map()}
  def create_response(interaction_id, interaction_token, type, data \\ nil, opts \\ []) do
    path = "/interactions/#{interaction_id}/#{interaction_token}/callback"
    type = Map.get(@response_types, type, type)
    params = Client.params(opts)

    body =
      case data do
        %{files: files} when is_list(files) ->
          [multipart: Body.multipart(%{type: type, data: Map.delete(data, :files)}, files)]

        nil ->
          [json: %{type: type}]

        data ->
          [json: %{type: type, data: data}]
      end

    result = Client.request(:post, path, [params: params] ++ body)
    # an interaction received over HTTP waits for this before answering 202
    Lingo.Endpoint.Pending.answered(Lingo.Instance.current(), interaction_id)
    result
  end

  @doc "Fetches the first response to an interaction."
  @spec get_original_response(String.t()) :: Api.result(Message.t())
  def get_original_response(interaction_token),
    do: message(:get, interaction_token, "messages/@original", [])

  @doc "Edits the first response to an interaction."
  @spec update_original_response(String.t(), Api.content()) :: Api.result(Message.t())
  def update_original_response(interaction_token, params),
    do: message(:patch, interaction_token, "messages/@original", Body.opts(params))

  @doc "Deletes the first response to an interaction."
  @spec delete_original_response(String.t()) :: Api.result()
  def delete_original_response(interaction_token),
    do: webhook(:delete, interaction_token, "messages/@original", [])

  @doc "Sends a follow-up message to an interaction."
  @spec create_followup(String.t(), Api.content()) :: Api.result(Message.t())
  def create_followup(interaction_token, params),
    do: message(:post, interaction_token, nil, Body.opts(params))

  @doc "Fetches a follow-up message."
  @spec get_followup(String.t(), Api.id()) :: Api.result(Message.t())
  def get_followup(interaction_token, message_id),
    do: message(:get, interaction_token, "messages/#{message_id}", [])

  @doc "Edits a follow-up message."
  @spec update_followup(String.t(), Api.id(), Api.content()) :: Api.result(Message.t())
  def update_followup(interaction_token, message_id, params),
    do: message(:patch, interaction_token, "messages/#{message_id}", Body.opts(params))

  @doc "Deletes a follow-up message."
  @spec delete_followup(String.t(), Api.id()) :: Api.result()
  def delete_followup(interaction_token, message_id),
    do: webhook(:delete, interaction_token, "messages/#{message_id}", [])

  defp message(method, token, path, opts) do
    with {:ok, data} <- webhook(method, token, path, opts), do: {:ok, Message.new(data)}
  end

  # interaction follow-ups go through the application's webhook
  defp webhook(method, token, path, opts) do
    with {:ok, app_id} <- Lingo.Instance.application_id() do
      base = "/webhooks/#{app_id}/#{token}"
      Client.request(method, if(path, do: "#{base}/#{path}", else: base), opts)
    end
  end
end
