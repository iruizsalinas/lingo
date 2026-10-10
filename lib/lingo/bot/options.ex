defmodule Lingo.Bot.Options do
  @moduledoc """
  Builders for application command options, imported by `use Lingo.Bot`.

      command "search", "Search the catalog",
        options: [
          string(:query, "What to look for", required: true, autocomplete: true),
          integer(:limit, "How many results", min_value: 1, max_value: 25),
          channel(:where, "Channel to post in", channel_types: [:guild_text])
        ]

  Names may be atoms or strings. Every builder takes these options:

    * `:required` - must be filled in (default `false`)
    * `:choices` - for strings and numbers, a fixed list of `%{name:, value:}`
      maps or `[name:, value:]` keyword lists
    * `:autocomplete` - suggest values from `c:Lingo.Bot.handle_autocomplete/2`
    * `:min_value`, `:max_value` - bounds for `integer/3` and `number/3`
    * `:min_length`, `:max_length` - bounds for `string/3`
    * `:channel_types` - channel types `channel/3` accepts
    * `:file_types` - file extensions `attachment/3` accepts, like `".pdf"`
      (Discord only checks the name)
    * `:options` - the nested options of `subcommand/3` and `subcommand_group/3`
    * `:name_localizations`, `:description_localizations` - maps of locale to text
  """

  alias Lingo.Type.CommandOption

  @type name :: atom() | String.t()

  @doc "A subcommand; its own options go in `:options`."
  @spec subcommand(name(), String.t(), keyword()) :: CommandOption.t()
  def subcommand(name, description, opts \\ []), do: build(:sub_command, name, description, opts)

  @doc "A group of subcommands, listed in `:options`."
  @spec subcommand_group(name(), String.t(), keyword()) :: CommandOption.t()
  def subcommand_group(name, description, opts \\ []),
    do: build(:sub_command_group, name, description, opts)

  @doc "A text option."
  @spec string(name(), String.t(), keyword()) :: CommandOption.t()
  def string(name, description, opts \\ []), do: build(:string, name, description, opts)

  @doc "An integer option."
  @spec integer(name(), String.t(), keyword()) :: CommandOption.t()
  def integer(name, description, opts \\ []), do: build(:integer, name, description, opts)

  @doc "A number option; the value may be a float."
  @spec number(name(), String.t(), keyword()) :: CommandOption.t()
  def number(name, description, opts \\ []), do: build(:number, name, description, opts)

  @doc "A true/false option."
  @spec boolean(name(), String.t(), keyword()) :: CommandOption.t()
  def boolean(name, description, opts \\ []), do: build(:boolean, name, description, opts)

  @doc "A user option. Its value is the id; `Lingo.Context.get_user/2` resolves it."
  @spec user(name(), String.t(), keyword()) :: CommandOption.t()
  def user(name, description, opts \\ []), do: build(:user, name, description, opts)

  @doc "A channel option. Its value is the id; `Lingo.Context.get_channel/2` resolves it."
  @spec channel(name(), String.t(), keyword()) :: CommandOption.t()
  def channel(name, description, opts \\ []), do: build(:channel, name, description, opts)

  @doc "A role option. Its value is the id; `Lingo.Context.get_role/2` resolves it."
  @spec role(name(), String.t(), keyword()) :: CommandOption.t()
  def role(name, description, opts \\ []), do: build(:role, name, description, opts)

  @doc "A user or role option. Its value is the id."
  @spec mentionable(name(), String.t(), keyword()) :: CommandOption.t()
  def mentionable(name, description, opts \\ []),
    do: build(:mentionable, name, description, opts)

  @doc "A file option. Its value is the id; `Lingo.Context.get_attachment/2` resolves it."
  @spec attachment(name(), String.t(), keyword()) :: CommandOption.t()
  def attachment(name, description, opts \\ []), do: build(:attachment, name, description, opts)

  defp build(type, name, description, opts) do
    %CommandOption{
      type: type,
      name: to_string(name),
      name_localizations: Keyword.get(opts, :name_localizations),
      description: description,
      description_localizations: Keyword.get(opts, :description_localizations),
      required: Keyword.get(opts, :required, false),
      choices: opts |> Keyword.get(:choices, []) |> Enum.map(&normalize_choice/1),
      options: Keyword.get(opts, :options, []),
      min_value: Keyword.get(opts, :min_value),
      max_value: Keyword.get(opts, :max_value),
      min_length: Keyword.get(opts, :min_length),
      max_length: Keyword.get(opts, :max_length),
      autocomplete: Keyword.get(opts, :autocomplete, false),
      channel_types: Keyword.get(opts, :channel_types, []),
      file_types: Keyword.get(opts, :file_types, [])
    }
  end

  defp normalize_choice([{_, _} | _] = choice),
    do: %{"name" => choice[:name], "value" => choice[:value]}

  defp normalize_choice(choice), do: choice
end
