defmodule Lingo.Api.Message.Search do
  @moduledoc false

  # Guild message search: list options become repeated query keys, and an
  # index Discord is still building is retried.

  alias Lingo.Rest.Client
  alias Lingo.Type.{Channel, Message, ThreadMember}

  @search_index_retries 3
  @search_index_short_delay 1_000
  @search_array_params ~w(
    channel_id
    author_type
    author_id
    mentions
    mentions_role_id
    replied_to_user_id
    replied_to_message_id
    has
    embed_type
    embed_provider
    link_hostname
    attachment_filename
    attachment_extension
  )a

  def run(guild_id, opts) do
    retries = Keyword.get(opts, :search_index_retries, @search_index_retries)
    short_delay = Keyword.get(opts, :search_index_short_delay, @search_index_short_delay)

    params =
      opts
      |> Keyword.drop([:search_index_retries, :search_index_short_delay])
      |> normalize_params()

    guild_id |> search(params, retries, short_delay) |> Client.into(&result/1)
  end

  defp search(guild_id, params, retries_left, short_delay) do
    case Client.request(:get, "/guilds/#{guild_id}/messages/search", params: params) do
      {:ok, %{"code" => 110_000} = body} when retries_left > 0 ->
        Process.sleep(retry_after(body, short_delay))
        search(guild_id, params, retries_left - 1, short_delay)

      {:ok, %{"code" => 110_000} = body} ->
        {:error, %Lingo.Error{reason: :index_not_ready, details: body}}

      result ->
        result
    end
  end

  defp result(data) do
    %{
      doing_deep_historical_index: data["doing_deep_historical_index"] || false,
      documents_indexed: data["documents_indexed"],
      total_results: data["total_results"] || 0,
      messages: Enum.map(data["messages"] || [], fn group -> Enum.map(group, &Message.new/1) end),
      threads: Enum.map(data["threads"] || [], &Channel.new/1),
      members: Enum.map(data["members"] || [], &ThreadMember.new/1)
    }
  end

  defp retry_after(%{"retry_after" => seconds}, short_delay) when is_number(seconds) do
    ms = trunc(seconds * 1000)
    if ms > 0, do: ms, else: short_delay
  end

  defp retry_after(_body, short_delay), do: short_delay

  defp normalize_params(params) do
    Enum.flat_map(params, fn
      {key, values} when key in @search_array_params and is_list(values) ->
        Enum.map(values, &{key, &1})

      param ->
        [param]
    end)
  end
end
