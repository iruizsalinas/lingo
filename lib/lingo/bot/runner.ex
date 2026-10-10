defmodule Lingo.Bot.Runner do
  @moduledoc false

  # Calls the bot module's callbacks, each in its own process under the bot's
  # Task.Supervisor, so a slow or crashing handler never holds up the gateway.
  # Commands pass their checks first; a crash is logged and handed to the
  # bot's handle_error/2, when it has one.

  require Logger

  alias Lingo.{CheckError, Context, EventError, Instance, Telemetry}
  alias Lingo.Bot.Checks

  @callbacks %{
    application_command: :handle_command,
    message_component: :handle_component,
    modal_submit: :handle_modal,
    autocomplete: :handle_autocomplete
  }

  @command_types %{1 => :chat_input, 2 => :user, 3 => :message, 4 => :primary_entry_point}

  @spec event(Lingo.Event.name(), Lingo.Event.payload()) :: :ok
  def event(event, data) do
    bot = Instance.get(:bot)

    if bot && function_exported?(bot, :handle_event, 2) do
      run(bot, {event, data}, fn ->
        Telemetry.span([:event], %{event: event}, fn -> {bot.handle_event(event, data), %{}} end)
      end)
    end

    :ok
  end

  @doc """
  An event Lingo couldn't parse: it never reaches handle_event/2, whose
  clauses expect the parsed payload, but goes to handle_error/2 as a
  Lingo.EventError with Discord's raw data.
  """
  @spec parse_failed(atom(), term(), Exception.t(), list()) :: :ok
  def parse_failed(event, data, exception, stacktrace) do
    Logger.error(
      "Lingo could not parse event #{inspect(event)}, dropping it\n" <>
        Exception.format(:error, exception, stacktrace)
    )

    Telemetry.execute([:event, :parse_failed], %{}, %{event: event})
    bot = Instance.get(:bot)

    if bot && function_exported?(bot, :handle_error, 2) do
      error = EventError.new(event, data, exception)
      run(bot, {event, data}, fn -> handle_error(bot, error, {event, data}) end)
    end

    :ok
  end

  @spec interaction(Lingo.Type.Interaction.t()) :: :ok
  def interaction(%Lingo.Type.Interaction{type: type} = interaction) do
    bot = Instance.get(:bot)
    callback = @callbacks[type]

    if callback && bot && function_exported?(bot, callback, 2) do
      ctx = Context.new(interaction, Instance.current())
      run(bot, ctx, fn -> call(bot, callback, ctx) end)
      :ok
    else
      # interactions the bot has no callback for still reach handle_event
      event(:interaction_create, interaction)
    end
  end

  defp call(bot, :handle_command, ctx) do
    type = Map.get(@command_types, ctx.interaction.data["type"], :chat_input)

    meta = %{
      command_name: ctx.command_name,
      type: type,
      guild_id: ctx.guild_id,
      user_id: ctx.user_id
    }

    Telemetry.span([:command], meta, fn ->
      result =
        case Checks.run(rules(bot, type, ctx), ctx) do
          :ok -> bot.handle_command(ctx.command_name, ctx)
          {:error, %CheckError{} = error} -> check_failed(bot, error, ctx)
        end

      {result, %{}}
    end)
  end

  defp call(bot, callback, ctx), do: apply(bot, callback, [route(ctx), ctx])

  @no_rules %{checks: [], cooldown: nil}

  defp rules(bot, type, ctx) do
    if function_exported?(bot, :__command_rules__, 0),
      do: Map.get(bot.__command_rules__(), {type, ctx.command_name}, @no_rules),
      else: @no_rules
  end

  defp check_failed(bot, error, ctx) do
    Telemetry.execute([:command, :check_failed], %{}, %{
      command_name: ctx.command_name,
      reason: error.reason
    })

    if function_exported?(bot, :handle_error, 2),
      do: bot.handle_error(error, ctx),
      else: Context.ephemeral(ctx, error.message)
  end

  defp route(%Context{type: :autocomplete, command_name: name}), do: name
  defp route(%Context{custom_id: custom_id}), do: custom_id

  defp run(bot, source, fun) do
    name = Instance.current()

    {:ok, _pid} =
      Task.Supervisor.start_child(Instance.process_name(name, Lingo.TaskSupervisor), fn ->
        Instance.put_current(name)

        try do
          fun.()
        catch
          kind, reason -> failed(bot, source, kind, reason, __STACKTRACE__)
        end
      end)

    :ok
  end

  defp failed(bot, source, kind, reason, stacktrace) do
    Logger.error(
      "#{inspect(bot)} failed handling #{describe(source)}\n" <>
        Exception.format(kind, reason, stacktrace)
    )

    if function_exported?(bot, :handle_error, 2) do
      error =
        if kind == :error,
          do: Exception.normalize(:error, reason, stacktrace),
          else: %ErlangError{original: {kind, reason}}

      handle_error(bot, error, source)
    end
  end

  defp handle_error(bot, error, source) do
    bot.handle_error(error, source)
  catch
    kind, reason ->
      Logger.error(
        "#{inspect(bot)}.handle_error/2 failed\n" <>
          Exception.format(kind, reason, __STACKTRACE__)
      )
  end

  defp describe(%Context{type: :application_command, command_name: name}),
    do: "command #{inspect(name)}"

  defp describe(%Context{type: :autocomplete, command_name: name}),
    do: "autocomplete for #{inspect(name)}"

  defp describe(%Context{type: type, custom_id: id}), do: "#{type} #{inspect(id)}"
  defp describe({event, _data}), do: "event #{inspect(event)}"
end
