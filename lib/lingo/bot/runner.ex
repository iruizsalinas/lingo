defmodule Lingo.Bot.Runner do
  @moduledoc false

  # Calls the bot module's callbacks, each in its own process under the bot's
  # Task.Supervisor, so a slow or crashing handler never holds up the gateway.

  alias Lingo.{Context, Instance}

  @callbacks %{
    application_command: :handle_command,
    message_component: :handle_component,
    modal_submit: :handle_modal,
    autocomplete: :handle_autocomplete
  }

  @spec event(atom(), term()) :: :ok
  def event(event, data) do
    bot = Instance.get(:bot)

    if bot && function_exported?(bot, :handle_event, 2) do
      run(fn -> bot.handle_event(event, data) end)
    end

    :ok
  end

  @spec interaction(Lingo.Type.Interaction.t()) :: :ok
  def interaction(%Lingo.Type.Interaction{type: type} = interaction) do
    bot = Instance.get(:bot)
    callback = @callbacks[type]

    if callback && bot && function_exported?(bot, callback, 2) do
      ctx = Context.new(interaction, Instance.current())
      run(fn -> apply(bot, callback, [route(ctx), ctx]) end)
      :ok
    else
      # interactions the bot has no callback for still reach handle_event
      event(:interaction_create, interaction)
    end
  end

  defp route(%Context{type: type, command_name: name})
       when type in [:application_command, :autocomplete],
       do: name

  defp route(%Context{custom_id: custom_id}), do: custom_id

  defp run(fun) do
    bot = Instance.current()

    {:ok, _pid} =
      Task.Supervisor.start_child(Instance.process_name(bot, Lingo.TaskSupervisor), fn ->
        Instance.put_current(bot)
        fun.()
      end)

    :ok
  end
end
