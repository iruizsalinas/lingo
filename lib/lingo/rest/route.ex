defmodule Lingo.Rest.Route do
  @moduledoc false

  # Groups requests into the rate limit buckets Discord uses: ids are
  # generalized away except the major parameters (channel, guild, webhook).

  import Bitwise

  @discord_epoch 1_420_070_400_000

  @doc "The bucket key for a request, like discord.js computes it."
  @spec key(atom(), String.t(), keyword()) :: String.t()
  def key(method, path, opts) do
    generalized =
      path
      |> String.split("/")
      |> generalize_path_segments()
      |> Enum.join("/")

    key = "#{method}:#{generalized}"

    # old message delete has a separate stricter bucket
    key = maybe_old_message_suffix(key, method, path)

    # channel name/topic edits have a sublimit
    maybe_channel_sublimit(key, method, path, opts)
  end

  defp generalize_path_segments([]), do: []

  # keep major params (channel_id, guild_id, webhook_id + webhook_token)
  defp generalize_path_segments(["webhooks", id, token | rest]) do
    if snowflake?(token) or token in ["messages"] do
      ["webhooks", id | generalize_path_segments([token | rest])]
    else
      ["webhooks", id, token | generalize_path_segments(rest)]
    end
  end

  defp generalize_path_segments([resource, id | rest])
       when resource in ~w(channels guilds webhooks) do
    [resource, id | generalize_path_segments(rest)]
  end

  # all reaction sub-routes share one bucket regardless of emoji
  defp generalize_path_segments(["reactions" | _rest]) do
    ["reactions", ":reaction"]
  end

  defp generalize_path_segments([segment | rest]) do
    if snowflake?(segment) do
      [":id" | generalize_path_segments(rest)]
    else
      [segment | generalize_path_segments(rest)]
    end
  end

  defp snowflake?(str) do
    case Integer.parse(str) do
      {n, ""} when n > 1_000_000 -> true
      _ -> false
    end
  end

  defp maybe_old_message_suffix(key, :delete, path) do
    case Regex.run(~r"/channels/\d+/messages/(\d+)$", path) do
      [_, message_id] ->
        ts = (String.to_integer(message_id) >>> 22) + @discord_epoch
        age_ms = System.system_time(:millisecond) - ts

        if age_ms > 14 * 24 * 60 * 60 * 1000 do
          key <> "/old"
        else
          key
        end

      _ ->
        key
    end
  end

  defp maybe_old_message_suffix(key, _method, _path), do: key

  defp maybe_channel_sublimit(key, :patch, path, opts) do
    if String.match?(path, ~r"^/channels/\d+$") do
      json = opts[:json]

      if is_map(json) and
           (Map.has_key?(json, :name) or Map.has_key?(json, :topic) or
              Map.has_key?(json, "name") or Map.has_key?(json, "topic")) do
        key <> "/name-topic"
      else
        key
      end
    else
      key
    end
  end

  defp maybe_channel_sublimit(key, _method, _path, _opts), do: key
end
