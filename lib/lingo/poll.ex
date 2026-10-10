defmodule Lingo.Poll do
  @moduledoc """
  Builds message polls.

      Lingo.Api.Message.create(channel_id, %{
        poll: Lingo.Poll.build("Pizza or pasta?", ["Pizza", {"Pasta", "🍝"}], duration: 48)
      })

  A sent poll comes back in `Lingo.Type.Message`'s `poll`; end it early with
  `Lingo.Api.Poll.expire/2`.
  """

  @doc """
  Builds a poll from its question and up to 10 answers. An answer is its
  text, or `{text, emoji}` with a unicode emoji or a custom one (a
  `Lingo.Type.Emoji`, or a map with its `:id`).

  Options: `:duration` (hours open, up to 768; Discord's default is 24) and
  `:multiselect` (whether users may pick several answers).
  """
  @spec build(String.t(), [String.t() | {String.t(), String.t() | map()}], keyword()) :: map()
  def build(question, answers, opts \\ []) when is_list(answers) do
    [
      question: %{text: question},
      answers: Enum.map(answers, &%{poll_media: media(&1)}),
      duration: opts[:duration],
      allow_multiselect: opts[:multiselect]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp media({text, emoji}), do: %{text: text, emoji: emoji(emoji)}
  defp media(text) when is_binary(text), do: %{text: text}

  defp emoji(%{id: id}) when not is_nil(id), do: %{id: id}
  defp emoji(%{name: name}), do: %{name: name}
  defp emoji(name) when is_binary(name), do: %{name: name}
end
