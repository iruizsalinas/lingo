defmodule Lingo.Bot.Compiler do
  @moduledoc false

  # Runs after a bot module's body: generates __commands__/0 and
  # __option_names__/0, adds catch-all clauses for the callbacks the bot
  # defines, and catches mistakes early.

  @interaction_callbacks [:handle_command, :handle_component, :handle_modal, :handle_autocomplete]

  defmacro __before_compile__(env) do
    commands = env.module |> Module.get_attribute(:lingo_commands) |> Enum.reverse()
    check_commands!(commands, env)

    defined =
      for callback <- [:handle_event | @interaction_callbacks],
          Module.defines?(env.module, {callback, 2}),
          do: callback

    if commands != [] and :handle_command not in defined do
      IO.warn("#{inspect(env.module)} declares commands but doesn't define handle_command/2", env)
    end

    if has_autocomplete?(commands) and :handle_autocomplete not in defined do
      IO.warn(
        "#{inspect(env.module)} has autocomplete options but doesn't define handle_autocomplete/2",
        env
      )
    end

    # declared option names must exist as atoms when interactions are parsed
    option_names = commands |> Enum.flat_map(& &1.options) |> option_names() |> Enum.uniq()

    rules = env.module |> Module.get_attribute(:lingo_command_rules) |> Map.new()

    quote do
      @doc false
      def __commands__, do: unquote(Macro.escape(commands))

      @doc false
      def __command_rules__, do: unquote(Macro.escape(rules))

      @doc false
      def __option_names__, do: unquote(Enum.map(option_names, &String.to_atom/1))

      unquote(catch_alls(defined))
    end
  end

  defp catch_alls(defined) do
    for callback <- defined do
      case callback do
        :handle_command ->
          quote generated: true do
            def handle_command(name, _ctx) do
              require Logger

              Logger.warning(
                "#{inspect(__MODULE__)} has no handle_command/2 clause for #{inspect(name)}"
              )

              :ok
            end
          end

        callback ->
          quote generated: true do
            def unquote(callback)(_key, _payload), do: :ok
          end
      end
    end
  end

  defp check_commands!(commands, env) do
    duplicates =
      commands
      |> Enum.frequencies_by(&{&1.type, &1.name})
      |> Enum.filter(fn {_key, count} -> count > 1 end)

    for {{type, name}, _count} <- duplicates do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "#{inspect(env.module)} declares the #{type} command #{inspect(name)} twice"
    end
  end

  defp option_names(options) do
    Enum.flat_map(options, fn option -> [option.name | option_names(option.options || [])] end)
  end

  defp has_autocomplete?(commands) do
    commands
    |> Enum.flat_map(&flatten_options(&1.options))
    |> Enum.any?(& &1.autocomplete)
  end

  defp flatten_options(options),
    do: Enum.flat_map(options, &[&1 | flatten_options(&1.options || [])])
end
