defmodule Lingo.Bot.Commands do
  @moduledoc """
  Declaring application commands, imported by `use Lingo.Bot`. Each declared
  command is handled in `c:Lingo.Bot.handle_command/2`.
  """

  @command_opts [
    :options,
    :default_member_permissions,
    :nsfw,
    :integration_types,
    :contexts,
    :name_localizations,
    :description_localizations
  ]

  @doc """
  Declares a slash command. Handle it in `c:Lingo.Bot.handle_command/2`.

  Options:

    * `:options` - the command's options, built with `Lingo.Bot.Options`
    * `:default_member_permissions` - permissions a member needs by default,
      as a bitfield (see `Lingo.Permissions.from_list/1`)
    * `:nsfw` - only usable in age-restricted channels
    * `:integration_types` - where it can be installed: `0` guild, `1` user
    * `:contexts` - where it can be used: `0` guild, `1` bot DM, `2` private channel
    * `:name_localizations`, `:description_localizations` - maps of locale to text
  """
  defmacro command(name, description, opts \\ []) do
    check_no_body!(opts, __CALLER__)

    quote bind_quoted: [name: name, description: description, opts: opts, keys: @command_opts] do
      Lingo.Bot.Commands.__validate_opts__!(opts, keys, :command)

      @lingo_commands %Lingo.Type.ApplicationCommand{
        name: to_string(name),
        description: description,
        options: Keyword.get(opts, :options, []),
        default_member_permissions: opts[:default_member_permissions],
        nsfw: Keyword.get(opts, :nsfw, false),
        integration_types: opts[:integration_types],
        contexts: opts[:contexts],
        name_localizations: opts[:name_localizations],
        description_localizations: opts[:description_localizations]
      }
    end
  end

  @doc """
  Declares a user context menu command (right click on a user). Handle it in
  `c:Lingo.Bot.handle_command/2`; the user is `ctx.target_id`.

  Takes the same options as `command/3`, except `:options` and
  `:description_localizations`.
  """
  defmacro user_command(name, opts \\ []), do: context_menu_command(:user, name, opts, __CALLER__)

  @doc """
  Declares a message context menu command (right click on a message). Handle
  it in `c:Lingo.Bot.handle_command/2`; the message is `ctx.target_id`.

  Takes the same options as `command/3`, except `:options` and
  `:description_localizations`.
  """
  defmacro message_command(name, opts \\ []),
    do: context_menu_command(:message, name, opts, __CALLER__)

  defp context_menu_command(type, name, opts, caller) do
    check_no_body!(opts, caller)
    keys = @command_opts -- [:options, :description_localizations]

    quote bind_quoted: [type: type, name: name, opts: opts, keys: keys] do
      Lingo.Bot.Commands.__validate_opts__!(opts, keys, type)

      @lingo_commands %Lingo.Type.ApplicationCommand{
        name: to_string(name),
        description: "",
        type: type,
        options: [],
        default_member_permissions: opts[:default_member_permissions],
        nsfw: Keyword.get(opts, :nsfw, false),
        integration_types: opts[:integration_types],
        contexts: opts[:contexts],
        name_localizations: opts[:name_localizations]
      }
    end
  end

  defp check_no_body!(opts, caller) do
    if is_list(opts) and Keyword.has_key?(opts, :do) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "commands no longer take a do block; declare the command and handle it in " <>
            "handle_command/2, for example:\n\n" <>
            "    command \"ping\", \"Responds with pong\"\n\n" <>
            "    @impl true\n" <>
            "    def handle_command(\"ping\", ctx), do: reply!(ctx, \"Pong!\")"
    end
  end

  @doc false
  def __validate_opts__!(opts, keys, kind) do
    case Keyword.keys(opts) -- keys do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown #{kind} options: #{inspect(unknown)}"
    end
  end
end
