defmodule Lingo.Component.Modal do
  @moduledoc """
  Builders for modals and their inputs. Open one with
  `Lingo.Context.show_modal/2`; the submission reaches
  `c:Lingo.Bot.handle_modal/2`, with field values keyed by custom id.

      show_modal!(ctx, Modal.modal("feedback", "Feedback", [
        Modal.label("Subject", Modal.text_input("subject", required: true)),
        Modal.label("Details", Modal.text_input("body", style: :paragraph))
      ]))
  """

  import Lingo.Component, only: [put: 3]

  @text_styles %{short: 1, paragraph: 2}

  @doc "A modal with a title and up to 5 labeled inputs."
  @spec modal(String.t(), String.t(), [map()]) :: map()
  def modal(custom_id, title, components),
    do: %{custom_id: custom_id, title: title, components: components}

  @doc "A label and optional `:description` around an input."
  @spec label(String.t(), map(), keyword()) :: map()
  def label(text, component, opts \\ []),
    do: %{type: 18, label: text, component: component} |> put(opts, [:description])

  @doc """
  A text field. Options: `:style` (`:short` or `:paragraph`), `:placeholder`,
  `:min_length`, `:max_length`, `:required` and `:value`. Wrap it in
  `label/3`, or give the label as the second argument.
  """
  @spec text_input(String.t(), String.t() | keyword(), keyword()) :: map()
  def text_input(custom_id, label_or_opts \\ [], opts \\ [])

  def text_input(custom_id, label, opts) when is_binary(label),
    do: custom_id |> text_input(opts) |> Map.put(:label, label)

  def text_input(custom_id, opts, _) when is_list(opts) do
    style = opts[:style] || :short

    %{type: 4, custom_id: custom_id, style: Map.get(@text_styles, style, style)}
    |> put(opts, [:placeholder, :min_length, :max_length, :required, :value])
  end

  @doc "A file upload field. Options: `:min_values`, `:max_values`, `:required` and `:file_types`."
  @spec file_upload(String.t(), keyword()) :: map()
  def file_upload(custom_id, opts \\ []),
    do:
      %{type: 19, custom_id: custom_id}
      |> put(opts, [:min_values, :max_values, :required, :file_types])

  @doc "A single-choice group. Option: `:required`."
  @spec radio_group(String.t(), [map()], keyword()) :: map()
  def radio_group(custom_id, options, opts \\ []),
    do: %{type: 21, custom_id: custom_id, options: options} |> put(opts, [:required])

  @doc "A multiple-choice group. Options: `:min_values`, `:max_values` and `:required`."
  @spec checkbox_group(String.t(), [map()], keyword()) :: map()
  def checkbox_group(custom_id, options, opts \\ []),
    do:
      %{type: 22, custom_id: custom_id, options: options}
      |> put(opts, [:min_values, :max_values, :required])

  @doc "A checkbox. Option: `:default`."
  @spec checkbox(String.t(), keyword()) :: map()
  def checkbox(custom_id, opts \\ []),
    do: %{type: 23, custom_id: custom_id} |> put(opts, [:default])
end
