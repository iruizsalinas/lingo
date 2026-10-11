defmodule Lingo.Type.Poll do
  @moduledoc """
  A message's poll. Build one to send with `Lingo.Poll.build/3`.

  `question` and each answer's `poll_media` are maps with atom keys holding
  the `text` and an optional `Lingo.Type.Emoji`. `results` holds the vote
  counts, once Discord has them; they're final when `is_finalized` is true.
  `layout_type` is `:default`, the only layout so far.
  """

  alias Lingo.Type.{Emoji, Parse}

  @type media :: %{text: String.t() | nil, emoji: Emoji.t() | nil}
  @type answer :: %{answer_id: integer(), poll_media: media()}
  @type answer_count :: %{id: integer(), count: integer(), me_voted: boolean()}
  @type results :: %{is_finalized: boolean(), answer_counts: [answer_count()]}
  @type t :: %__MODULE__{
          question: media(),
          answers: [answer()],
          expiry: DateTime.t() | nil,
          allow_multiselect: boolean(),
          layout_type: :default | integer(),
          results: results() | nil
        }

  defstruct [
    :question,
    :expiry,
    :results,
    answers: [],
    allow_multiselect: false,
    layout_type: :default
  ]

  @layout_types %{1 => :default}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      question: media(data["question"]),
      answers: Parse.list(data["answers"], &answer/1),
      expiry: Parse.timestamp(data["expiry"]),
      allow_multiselect: data["allow_multiselect"] || false,
      layout_type: Map.get(@layout_types, data["layout_type"], data["layout_type"] || :default),
      results: results(data["results"])
    }
  end

  defp media(nil), do: nil
  defp media(data), do: %{text: data["text"], emoji: Emoji.new(data["emoji"])}

  defp answer(data), do: %{answer_id: data["answer_id"], poll_media: media(data["poll_media"])}

  defp results(nil), do: nil

  defp results(data) do
    %{
      is_finalized: data["is_finalized"] || false,
      answer_counts: Parse.list(data["answer_counts"], &answer_count/1)
    }
  end

  defp answer_count(data),
    do: %{id: data["id"], count: data["count"] || 0, me_voted: data["me_voted"] || false}
end
