defmodule Lingo.Embed do
  @moduledoc """
  Builds message embeds.

      Lingo.Api.Message.create(channel_id, %{
        embeds: [Lingo.Embed.build(title: "Results", color: 0x57F287, fields: [%{name: "Score", value: "42"}])]
      })

  Embeds Discord sends back are `Lingo.Type.Embed` structs.
  """

  @doc """
  Builds an embed from options: `:title`, `:description`, `:url`,
  `:color` (an integer like `0x5865F2`), `:timestamp` (a `DateTime`),
  `:image` and `:thumbnail` (URLs), `:footer` (text), `:author` (a name)
  and `:fields` (maps with `:name`, `:value` and `:inline`).

  `:image`, `:thumbnail`, `:footer` and `:author` also take the full maps
  Discord expects.
  """
  @spec build(keyword()) :: map()
  def build(opts) when is_list(opts) do
    [
      title: opts[:title],
      description: opts[:description],
      url: opts[:url],
      color: opts[:color],
      timestamp: opts[:timestamp],
      image: wrap(opts[:image], :url),
      thumbnail: wrap(opts[:thumbnail], :url),
      footer: wrap(opts[:footer], :text),
      author: wrap(opts[:author], :name),
      fields: if(opts[:fields] != [], do: opts[:fields])
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp wrap(nil, _key), do: nil
  defp wrap(value, key) when is_binary(value), do: %{key => value}
  defp wrap(map, _key) when is_map(map), do: map
end
