defmodule Lingo.Type.Component do
  @moduledoc false

  import Bitwise

  @type component_type ::
          :action_row
          | :button
          | :string_select
          | :text_input
          | :user_select
          | :role_select
          | :mentionable_select
          | :channel_select
          | :section
          | :text_display
          | :thumbnail
          | :media_gallery
          | :file
          | :separator
          | :container
          | :label
          | :file_upload
          | :radio_group
          | :checkbox_group
          | :checkbox

  @type button_style :: :primary | :secondary | :success | :danger | :link | :premium

  @type t :: %__MODULE__{
          type: component_type(),
          custom_id: String.t() | nil,
          style: button_style() | integer() | nil,
          label: String.t() | nil,
          emoji: map() | nil,
          url: String.t() | nil,
          disabled: boolean(),
          components: [t()],
          options: [map()],
          placeholder: String.t() | nil,
          min_values: integer() | nil,
          max_values: integer() | nil,
          min_length: integer() | nil,
          max_length: integer() | nil,
          required: boolean(),
          value: String.t() | nil
        }

  defstruct [
    :type,
    :custom_id,
    :style,
    :label,
    :emoji,
    :url,
    :placeholder,
    :min_values,
    :max_values,
    :min_length,
    :max_length,
    :value,
    disabled: false,
    components: [],
    options: [],
    required: false
  ]

  @components_v2 1 <<< 15

  @button_styles %{
    1 => :primary,
    2 => :secondary,
    3 => :success,
    4 => :danger,
    5 => :link,
    6 => :premium
  }
  @button_styles_reverse Map.new(@button_styles, fn {k, v} -> {v, k} end)

  @separator_spacings %{small: 1, large: 2}

  # Flag

  @spec v2() :: integer()
  def v2, do: @components_v2

  # V1 builders

  @spec action_row([map()]) :: map()
  def action_row(components) do
    %{type: 1, components: components}
  end

  @spec button(keyword()) :: map()
  def button(opts) do
    %{type: 2, style: encode_style(opts[:style] || :primary)}
    |> put_if(:custom_id, opts[:custom_id])
    |> put_if(:label, opts[:label])
    |> put_if(:emoji, opts[:emoji])
    |> put_if(:url, opts[:url])
    |> put_if(:disabled, if(opts[:disabled], do: true, else: nil))
    |> put_if(:sku_id, opts[:sku_id])
  end

  @spec string_select(String.t(), keyword()) :: map()
  def string_select(custom_id, opts \\ []) do
    %{type: 3, custom_id: custom_id}
    |> put_if(:options, non_empty(opts[:options]))
    |> put_if(:placeholder, opts[:placeholder])
    |> put_if(:min_values, opts[:min_values])
    |> put_if(:max_values, opts[:max_values])
    |> put_if(:disabled, if(opts[:disabled], do: true, else: nil))
  end

  @spec text_input(String.t(), String.t() | keyword(), keyword()) :: map()
  def text_input(custom_id, label_or_opts \\ [], opts \\ [])

  def text_input(custom_id, label, opts) when is_binary(label) do
    build_text_input(custom_id, opts)
    |> Map.put(:label, label)
  end

  def text_input(custom_id, opts, _) when is_list(opts) do
    build_text_input(custom_id, opts)
  end

  defp build_text_input(custom_id, opts) do
    style = if opts[:style] == :paragraph, do: 2, else: 1

    %{type: 4, custom_id: custom_id, style: style}
    |> put_if(:placeholder, opts[:placeholder])
    |> put_if(:min_length, opts[:min_length])
    |> put_if(:max_length, opts[:max_length])
    |> put_if(:required, if(opts[:required], do: true, else: nil))
    |> put_if(:value, opts[:value])
  end

  @spec user_select(String.t(), keyword()) :: map()
  def user_select(custom_id, opts \\ []) do
    %{type: 5, custom_id: custom_id}
    |> put_if(:placeholder, opts[:placeholder])
    |> put_if(:min_values, opts[:min_values])
    |> put_if(:max_values, opts[:max_values])
    |> put_if(:default_values, non_empty(opts[:default_values]))
    |> put_if(:disabled, if(opts[:disabled], do: true, else: nil))
  end

  @spec role_select(String.t(), keyword()) :: map()
  def role_select(custom_id, opts \\ []) do
    %{type: 6, custom_id: custom_id}
    |> put_if(:placeholder, opts[:placeholder])
    |> put_if(:min_values, opts[:min_values])
    |> put_if(:max_values, opts[:max_values])
    |> put_if(:default_values, non_empty(opts[:default_values]))
    |> put_if(:disabled, if(opts[:disabled], do: true, else: nil))
  end

  @spec mentionable_select(String.t(), keyword()) :: map()
  def mentionable_select(custom_id, opts \\ []) do
    %{type: 7, custom_id: custom_id}
    |> put_if(:placeholder, opts[:placeholder])
    |> put_if(:min_values, opts[:min_values])
    |> put_if(:max_values, opts[:max_values])
    |> put_if(:default_values, non_empty(opts[:default_values]))
    |> put_if(:disabled, if(opts[:disabled], do: true, else: nil))
  end

  @spec channel_select(String.t(), keyword()) :: map()
  def channel_select(custom_id, opts \\ []) do
    %{type: 8, custom_id: custom_id}
    |> put_if(:placeholder, opts[:placeholder])
    |> put_if(:min_values, opts[:min_values])
    |> put_if(:max_values, opts[:max_values])
    |> put_if(:default_values, non_empty(opts[:default_values]))
    |> put_if(:channel_types, non_empty(opts[:channel_types]))
    |> put_if(:disabled, if(opts[:disabled], do: true, else: nil))
  end

  # V2 message components

  @spec section([map()], map()) :: map()
  def section(text_displays, accessory) do
    %{type: 9, components: text_displays, accessory: accessory}
  end

  @spec text_display(String.t()) :: map()
  def text_display(content) do
    %{type: 10, content: content}
  end

  @spec thumbnail(String.t(), keyword()) :: map()
  def thumbnail(url, opts \\ []) do
    %{type: 11, media: %{url: url}}
    |> put_if(:description, opts[:description])
    |> put_if(:spoiler, if(opts[:spoiler], do: true, else: nil))
  end

  @spec media_gallery([map()]) :: map()
  def media_gallery(items) do
    %{type: 12, items: items}
  end

  @spec file(String.t(), keyword()) :: map()
  def file(url, opts \\ []) do
    %{type: 13, file: %{url: url}}
    |> put_if(:spoiler, if(opts[:spoiler], do: true, else: nil))
  end

  @spec separator(keyword()) :: map()
  def separator(opts \\ []) do
    %{type: 14}
    |> put_if(:divider, opts[:divider])
    |> put_if(:spacing, encode_spacing(opts[:spacing]))
  end

  @spec container([map()], keyword()) :: map()
  def container(components, opts \\ []) do
    %{type: 17, components: components}
    |> put_if(:accent_color, opts[:accent_color])
    |> put_if(:spoiler, if(opts[:spoiler], do: true, else: nil))
  end

  # Modal components

  @spec label(String.t(), map(), keyword()) :: map()
  def label(label_text, component, opts \\ []) do
    %{type: 18, label: label_text, component: component}
    |> put_if(:description, opts[:description])
  end

  @spec file_upload(String.t(), keyword()) :: map()
  def file_upload(custom_id, opts \\ []) do
    %{type: 19, custom_id: custom_id}
    |> put_if(:min_values, opts[:min_values])
    |> put_if(:max_values, opts[:max_values])
    |> put_if(:required, opts[:required])
  end

  @spec radio_group(String.t(), [map()], keyword()) :: map()
  def radio_group(custom_id, options, opts \\ []) do
    %{type: 21, custom_id: custom_id, options: options}
    |> put_if(:required, opts[:required])
  end

  @spec checkbox_group(String.t(), [map()], keyword()) :: map()
  def checkbox_group(custom_id, options, opts \\ []) do
    %{type: 22, custom_id: custom_id, options: options}
    |> put_if(:min_values, opts[:min_values])
    |> put_if(:max_values, opts[:max_values])
  end

  @spec checkbox(String.t(), keyword()) :: map()
  def checkbox(custom_id, opts \\ []) do
    %{type: 23, custom_id: custom_id}
    |> put_if(:default, opts[:default])
  end

  # Helpers

  @spec modal(String.t(), String.t(), [map()]) :: map()
  def modal(custom_id, title, components) do
    %{custom_id: custom_id, title: title, components: components}
  end

  @spec gallery_item(String.t(), keyword()) :: map()
  def gallery_item(url, opts \\ []) do
    %{media: %{url: url}}
    |> put_if(:description, opts[:description])
    |> put_if(:spoiler, if(opts[:spoiler], do: true, else: nil))
  end

  @spec unfurled_media(String.t()) :: map()
  def unfurled_media(url) do
    %{url: url}
  end

  @spec select_option(String.t(), String.t(), keyword()) :: map()
  def select_option(label, value, opts \\ []) do
    %{label: label, value: value}
    |> put_if(:description, opts[:description])
    |> put_if(:emoji, opts[:emoji])
    |> put_if(:default, if(opts[:default], do: true, else: nil))
  end

  @spec default_value(String.t(), String.t() | atom()) :: map()
  def default_value(id, type) when type in ["user", "role", "channel"] do
    %{id: id, type: type}
  end

  def default_value(id, type) when type in [:user, :role, :channel] do
    %{id: id, type: Atom.to_string(type)}
  end

  # Private

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp encode_style(style) when is_atom(style), do: Map.get(@button_styles_reverse, style, style)
  defp encode_style(style), do: style

  defp encode_spacing(nil), do: nil

  defp encode_spacing(spacing) when is_atom(spacing),
    do: Map.get(@separator_spacings, spacing, spacing)

  defp encode_spacing(spacing), do: spacing

  defp non_empty(nil), do: nil
  defp non_empty([]), do: nil
  defp non_empty(list), do: list
end
