defmodule Lingo.Context.Parse do
  @moduledoc false

  # Builds a Lingo.Context from an interaction, turning its raw options and
  # modal components into maps.

  alias Lingo.Context
  alias Lingo.Type.Interaction

  @component_types %{
    2 => :button,
    3 => :string_select,
    5 => :user_select,
    6 => :role_select,
    7 => :mentionable_select,
    8 => :channel_select
  }

  @spec context(Interaction.t(), atom() | nil) :: Context.t()
  def context(%Interaction{} = i, bot) do
    user = Interaction.author(i)
    data = i.data || %{}

    ctx = %Context{
      bot: bot,
      type: i.type,
      interaction_id: i.id,
      interaction_token: i.token,
      application_id: i.application_id,
      guild_id: i.guild_id,
      channel_id: i.channel_id,
      user_id: user && user.id,
      member: i.member,
      user: user,
      locale: i.locale,
      guild_locale: i.guild_locale,
      app_permissions: i.app_permissions,
      message: i.message,
      resolved: data["resolved"],
      interaction: i
    }

    case i.type do
      type when type in [:application_command, :autocomplete] ->
        %{
          ctx
          | command_name: data["name"],
            options: options(data["options"]),
            raw_options: data["options"],
            target_id: data["target_id"]
        }

      :message_component ->
        type = data["component_type"]
        values = data["values"] || []

        %{
          ctx
          | custom_id: data["custom_id"],
            values: values,
            component_type: Map.get(@component_types, type, type)
        }

      :modal_submit ->
        %{ctx | custom_id: data["custom_id"], options: modal(data["components"])}

      _other ->
        ctx
    end
  end

  @spec options([map()] | nil) :: map()
  def options(nil), do: %{}

  # sub_command (1) and sub_command_group (2) nest their options
  def options(options) when is_list(options) do
    Enum.reduce(options, %{}, fn
      %{"type" => type, "name" => name} = opt, acc when type in [1, 2] ->
        Map.put(acc, key(name), options(opt["options"]))

      %{"name" => name, "value" => value}, acc ->
        Map.put(acc, key(name), value)

      _other, acc ->
        acc
    end)
  end

  @spec modal([map()] | nil) :: %{String.t() => term()}
  def modal(nil), do: %{}
  def modal(components) when is_list(components), do: Enum.reduce(components, %{}, &field/2)

  @spec focused([map()] | nil) :: {atom() | String.t(), term()} | nil
  def focused(nil), do: nil
  def focused([]), do: nil

  def focused([%{"focused" => true, "name" => name, "value" => value} | _]),
    do: {key(name), value}

  def focused([%{"options" => nested} | _]) when is_list(nested), do: focused(nested)
  def focused([_ | rest]), do: focused(rest)

  # option names a bot declared exist as atoms (Lingo.Bot keeps them alive), so
  # those come out as atoms and anything else stays a string
  @spec key(String.t()) :: atom() | String.t()
  def key(name) do
    case existing_atom(name) do
      {:ok, atom} -> atom
      :error -> name
    end
  end

  @spec existing_atom(String.t()) :: {:ok, atom()} | :error
  def existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  # action rows (1) and labels (18) wrap the actual inputs
  defp field(%{"type" => 1, "components" => children}, acc) when is_list(children),
    do: Enum.reduce(children, acc, &field/2)

  defp field(%{"type" => 18, "component" => child}, acc) when is_map(child), do: field(child, acc)
  defp field(%{"custom_id" => id, "value" => value}, acc), do: Map.put(acc, id, value)

  defp field(%{"custom_id" => id, "values" => values}, acc) when is_list(values),
    do: Map.put(acc, id, values)

  defp field(_component, acc), do: acc
end
