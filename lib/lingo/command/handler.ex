defmodule Lingo.Command.Handler do
  @moduledoc false

  alias Lingo.Command.Context

  @spec handle_interaction(Lingo.Type.Interaction.t()) :: :ok
  def handle_interaction(%{type: :application_command} = interaction) do
    ctx = Context.from_interaction(interaction)
    bot_module = Lingo.Config.bot_module()

    Code.ensure_loaded(bot_module)

    if bot_module && function_exported?(bot_module, :__handle_command__, 2) do
      Task.start(fn ->
        bot_module.__handle_command__(ctx.command_name, ctx)
      end)
    end

    :ok
  end

  def handle_interaction(%{type: :message_component} = interaction) do
    bot_module = Lingo.Config.bot_module()
    Code.ensure_loaded(bot_module)

    if bot_module && function_exported?(bot_module, :__handle_component__, 2) do
      ctx = Context.from_component(interaction)

      Task.start(fn ->
        bot_module.__handle_component__(ctx.custom_id, ctx)
      end)
    else
      dispatch_event_fallback(interaction)
    end

    :ok
  end

  def handle_interaction(%{type: :autocomplete} = interaction) do
    dispatch_autocomplete(interaction)
  end

  def handle_interaction(%{type: :modal_submit} = interaction) do
    bot_module = Lingo.Config.bot_module()
    Code.ensure_loaded(bot_module)

    if bot_module && function_exported?(bot_module, :__handle_modal__, 2) do
      ctx = Context.from_modal(interaction)

      Task.start(fn ->
        bot_module.__handle_modal__(ctx.custom_id, ctx)
      end)
    else
      dispatch_event_fallback(interaction)
    end

    :ok
  end

  def handle_interaction(_interaction), do: :ok

  defp dispatch_event_fallback(interaction) do
    bot_module = Lingo.Config.bot_module()

    if bot_module && function_exported?(bot_module, :__handle_event__, 2) do
      Task.start(fn ->
        bot_module.__handle_event__(:interaction_create, interaction)
      end)
    end

    :ok
  end

  defp dispatch_autocomplete(interaction) do
    bot_module = Lingo.Config.bot_module()

    if bot_module && function_exported?(bot_module, :__handle_autocomplete__, 2) do
      ctx = Context.from_interaction(interaction)

      Task.start(fn ->
        bot_module.__handle_autocomplete__(ctx.command_name, ctx)
      end)
    end

    :ok
  end
end
