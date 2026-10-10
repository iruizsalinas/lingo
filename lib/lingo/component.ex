defmodule Lingo.Component do
  @moduledoc """
  Builders for message components: buttons and select menus. They return the
  maps Discord expects.

      Lingo.Api.Message.create(channel_id, %{
        content: "Pick one",
        components: [
          Lingo.Component.action_row([
            Lingo.Component.button(custom_id: "vote:yes", label: "Yes", style: :success),
            Lingo.Component.button(custom_id: "vote:no", label: "No", style: :danger)
          ])
        ]
      })

  Clicks reach `c:Lingo.Bot.handle_component/2`. Layout components are in
  `Lingo.Component.Layout` and modal inputs in `Lingo.Component.Modal`.
  """

  import Bitwise

  @button_styles %{primary: 1, secondary: 2, success: 3, danger: 4, link: 5, premium: 6}
  @select_keys [:placeholder, :min_values, :max_values, :default_values, :required, :disabled]

  @doc "The message flag that enables components v2 (`Lingo.Component.Layout`). Put it in `:flags`."
  @spec v2() :: integer()
  def v2, do: 1 <<< 15

  @doc "A row of up to 5 buttons, or 1 select menu."
  @spec action_row([map()]) :: map()
  def action_row(components), do: %{type: 1, components: components}

  @doc """
  A button. Options: `:style` (`:primary`, `:secondary`, `:success`,
  `:danger`, `:link` or `:premium`), `:custom_id` (or `:url` for links),
  `:label`, `:emoji`, `:disabled` and `:sku_id` (for premium buttons).
  """
  @spec button(keyword()) :: map()
  def button(opts) do
    style = opts[:style] || :primary

    %{type: 2, style: Map.get(@button_styles, style, style)}
    |> put(opts, [:custom_id, :label, :emoji, :url, :disabled, :sku_id])
  end

  @doc """
  A select menu of your own choices, built with `select_option/3`. Options:
  `:options`, `:placeholder`, `:min_values`, `:max_values`, `:required` and
  `:disabled`.
  """
  @spec string_select(String.t(), keyword()) :: map()
  def string_select(custom_id, opts \\ []),
    do:
      %{type: 3, custom_id: custom_id}
      |> put(opts, [:options | @select_keys -- [:default_values]])

  @doc """
  A select menu of users. Options: `:placeholder`, `:min_values`,
  `:max_values`, `:default_values` (see `default_value/2`), `:required` and
  `:disabled`.
  """
  @spec user_select(String.t(), keyword()) :: map()
  def user_select(custom_id, opts \\ []), do: select(5, custom_id, opts)

  @doc "A select menu of roles. Takes the same options as `user_select/2`."
  @spec role_select(String.t(), keyword()) :: map()
  def role_select(custom_id, opts \\ []), do: select(6, custom_id, opts)

  @doc "A select menu of users and roles. Takes the same options as `user_select/2`."
  @spec mentionable_select(String.t(), keyword()) :: map()
  def mentionable_select(custom_id, opts \\ []), do: select(7, custom_id, opts)

  @doc "A select menu of channels. Takes the options of `user_select/2`, plus `:channel_types`."
  @spec channel_select(String.t(), keyword()) :: map()
  def channel_select(custom_id, opts \\ []) do
    types =
      opts[:channel_types] &&
        Enum.map(opts[:channel_types], &Lingo.Type.Codes.code(:channel_type, &1))

    select(8, custom_id, Keyword.put(opts, :channel_types, types))
  end

  @doc "One choice in a `string_select/2`. Options: `:description`, `:emoji` and `:default`."
  @spec select_option(String.t(), String.t(), keyword()) :: map()
  def select_option(label, value, opts \\ []),
    do: %{label: label, value: value} |> put(opts, [:description, :emoji, :default])

  @doc "A preselected entry for a user, role, mentionable or channel select: `type` is `:user`, `:role` or `:channel`."
  @spec default_value(String.t(), String.t() | atom()) :: map()
  def default_value(id, type) when is_atom(type), do: %{id: id, type: Atom.to_string(type)}
  def default_value(id, type), do: %{id: id, type: type}

  defp select(type, custom_id, opts),
    do: %{type: type, custom_id: custom_id} |> put(opts, [:channel_types | @select_keys])

  @doc false
  # copies the given options that are set
  @spec put(map(), keyword(), [atom()]) :: map()
  def put(map, opts, keys) do
    Enum.reduce(keys, map, fn key, acc ->
      case opts[key] do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end
end
