defmodule Lingo.Bot.OptionBuilders do
  @moduledoc false

  alias Lingo.Type.CommandOption

  def subcommand(name, description, opts \\ []) do
    build_option(:sub_command, name, description, opts)
  end

  def subcommand_group(name, description, opts \\ []) do
    build_option(:sub_command_group, name, description, opts)
  end

  def string(name, description, opts \\ []) do
    build_option(:string, name, description, opts)
  end

  def integer(name, description, opts \\ []) do
    build_option(:integer, name, description, opts)
  end

  def boolean(name, description, opts \\ []) do
    build_option(:boolean, name, description, opts)
  end

  def user(name, description, opts \\ []) do
    build_option(:user, name, description, opts)
  end

  def channel(name, description, opts \\ []) do
    build_option(:channel, name, description, opts)
  end

  def role(name, description, opts \\ []) do
    build_option(:role, name, description, opts)
  end

  def mentionable(name, description, opts \\ []) do
    build_option(:mentionable, name, description, opts)
  end

  def number(name, description, opts \\ []) do
    build_option(:number, name, description, opts)
  end

  def attachment(name, description, opts \\ []) do
    build_option(:attachment, name, description, opts)
  end

  defp build_option(type, name, description, opts) do
    %CommandOption{
      type: type,
      name: name,
      name_localizations: Keyword.get(opts, :name_localizations),
      description: description,
      description_localizations: Keyword.get(opts, :description_localizations),
      required: Keyword.get(opts, :required, false),
      choices: opts |> Keyword.get(:choices, []) |> normalize_choices(),
      options: Keyword.get(opts, :options, []),
      min_value: Keyword.get(opts, :min_value),
      max_value: Keyword.get(opts, :max_value),
      min_length: Keyword.get(opts, :min_length),
      max_length: Keyword.get(opts, :max_length),
      autocomplete: Keyword.get(opts, :autocomplete, false),
      channel_types: Keyword.get(opts, :channel_types, [])
    }
  end

  defp normalize_choices(choices) do
    Enum.map(choices, fn
      %{} = map -> map
      [{_, _} | _] = kw -> %{"name" => kw[:name], "value" => kw[:value]}
      other -> other
    end)
  end
end
