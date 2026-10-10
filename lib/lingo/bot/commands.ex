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
    :description_localizations,
    :checks,
    :cooldown
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
    * `:checks` - what must hold for the command to run, checked before
      `c:Lingo.Bot.handle_command/2`: `:guild_only`, `:dm_only`, `:nsfw`,
      `:owner_only` (the app's owner, or its team's owner, admins and
      developers), `{:permissions, perms}` (the member's, in the channel),
      `{:bot_permissions, perms}`, or a function like `&MyBot.allowed?/1`
      getting the context and returning `true` or `:ok` to pass, `false` or
      `{:error, message}` to fail. Permission checks fail as `:guild_only`
      outside a guild. See `Lingo.CheckError` for what happens when one
      fails. They don't replace `:default_member_permissions`, which also
      hides the command from members without them.
    * `:cooldown` - `{uses, per_ms}`, `{uses, per_ms, scope}` or
      `[uses: n, per: ms, scope: s]`: at most `uses` per `per_ms` for each
      `:user` (the default), `:member`, `:guild`, `:channel`, or `:global`ly.
      The window starts at the first use. A function like
      `&MyBot.cooldown/1` decides for each use: it gets the context and
      returns a cooldown, or `nil` for none (for owners, premium users...).
      Cooldowns count per node.

  For example:

      command "ban", "Bans a member",
        options: [user(:member, "Who", required: true)],
        checks: [:guild_only, {:permissions, [:ban_members]}, {:bot_permissions, [:ban_members]}],
        cooldown: {1, 5_000}
  """
  defmacro command(name, description, opts \\ []) do
    check_no_body!(opts, __CALLER__)

    quote bind_quoted: [name: name, description: description, opts: opts, keys: @command_opts] do
      Lingo.Bot.Commands.__validate_opts__!(opts, keys, :command)

      @lingo_commands Lingo.Bot.Commands.__command__(:chat_input, name, description, opts)

      if rules = Lingo.Bot.Commands.__rules__(:chat_input, name, opts),
        do: @lingo_command_rules(rules)
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

      @lingo_commands Lingo.Bot.Commands.__command__(type, name, "", opts)

      if rules = Lingo.Bot.Commands.__rules__(type, name, opts),
        do: @lingo_command_rules(rules)
    end
  end

  @doc """
  Declares the app's entry point command, which opens its Activity from the
  App Launcher. An app has at most one, and it's always global, so
  registering for guilds leaves it out.

  Enabling Activities makes Discord create one named "Launch", and
  registering keeps that one while the bot declares none: declare it only to
  change it.

  Takes the options of `command/3` except `:options`, plus `:handler`:
  `:discord_launch_activity` (the default) has Discord launch the Activity
  itself, and `:app_handler` sends the command to
  `c:Lingo.Bot.handle_command/2`, to answer with
  `Lingo.Context.launch_activity/1` or anything else.
  """
  defmacro entry_point_command(name, description, opts \\ []) do
    check_no_body!(opts, __CALLER__)
    keys = [:handler | @command_opts -- [:options]]

    quote bind_quoted: [name: name, description: description, opts: opts, keys: keys] do
      Lingo.Bot.Commands.__validate_opts__!(opts, keys, :entry_point_command)

      @lingo_commands Lingo.Bot.Commands.__command__(
                        :primary_entry_point,
                        name,
                        description,
                        opts
                      )

      if rules = Lingo.Bot.Commands.__rules__(:primary_entry_point, name, opts),
        do: @lingo_command_rules(rules)
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

  @handlers %{app_handler: 1, discord_launch_activity: 2}

  @doc false
  def __command__(type, name, description, opts) do
    %Lingo.Type.ApplicationCommand{
      name: to_string(name),
      description: description,
      type: type,
      options: Keyword.get(opts, :options, []),
      default_member_permissions: opts[:default_member_permissions],
      nsfw: Keyword.get(opts, :nsfw, false),
      integration_types: opts[:integration_types],
      contexts: opts[:contexts],
      name_localizations: opts[:name_localizations],
      description_localizations: opts[:description_localizations],
      handler: handler(type, opts[:handler])
    }
  end

  defp handler(:primary_entry_point, nil), do: @handlers.discord_launch_activity

  defp handler(:primary_entry_point, handler) do
    Map.get(@handlers, handler) ||
      raise ArgumentError,
            ":handler must be :app_handler or :discord_launch_activity, got: #{inspect(handler)}"
  end

  defp handler(_type, _handler), do: nil

  @doc false
  def __rules__(type, name, opts) do
    checks = Lingo.Bot.Checks.validate!(Keyword.get(opts, :checks, []))
    cooldown = Lingo.Bot.Cooldowns.validate!(opts[:cooldown])

    if checks != [] or cooldown,
      do: {{type, to_string(name)}, %{type: type, checks: checks, cooldown: cooldown}}
  end

  @doc false
  def __validate_opts__!(opts, keys, kind) do
    case Keyword.keys(opts) -- keys do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown #{kind} options: #{inspect(unknown)}"
    end
  end
end
