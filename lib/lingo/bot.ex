defmodule Lingo.Bot do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import Lingo.Bot,
        only: [
          command: 3,
          command: 4,
          handle: 3,
          autocomplete: 3,
          component: 3,
          modal: 3,
          user_command: 2,
          message_command: 2
        ]

      import Lingo.Command.Context,
        only: [
          reply: 2,
          reply!: 2,
          update: 2,
          update!: 2,
          defer: 1,
          defer: 2,
          defer!: 1,
          defer!: 2,
          option: 2,
          modal_value: 2,
          ephemeral: 2,
          show_modal: 2,
          show_modal!: 2,
          autocomplete_result: 2,
          focused_option: 1,
          resolved_user: 2,
          resolved_member: 2,
          resolved_role: 2,
          resolved_channel: 2,
          resolved_message: 2,
          resolved_attachment: 2,
          get_user: 2,
          get_role: 2,
          get_channel: 2,
          get_member: 2
        ]

      import Lingo.Bot.OptionBuilders

      Module.register_attribute(__MODULE__, :lingo_commands, accumulate: true)
      Module.register_attribute(__MODULE__, :lingo_handlers, accumulate: true)
      Module.register_attribute(__MODULE__, :lingo_autocompletes, accumulate: true)
      Module.register_attribute(__MODULE__, :lingo_components, accumulate: true)
      Module.register_attribute(__MODULE__, :lingo_modals, accumulate: true)

      @before_compile Lingo.Bot
    end
  end

  defmacro command(name, description, opts \\ [], do: body) do
    func_name = :"__cmd_#{name}__"

    options_ast = Keyword.get(opts, :options, [])
    permissions_ast = Keyword.get(opts, :default_member_permissions)
    nsfw_ast = Keyword.get(opts, :nsfw, false)
    integration_types_ast = Keyword.get(opts, :integration_types)
    contexts_ast = Keyword.get(opts, :contexts)

    quote do
      @lingo_commands %Lingo.Type.ApplicationCommand{
        name: unquote(name),
        description: unquote(description),
        options: unquote(options_ast),
        default_member_permissions: unquote(permissions_ast),
        nsfw: unquote(nsfw_ast),
        integration_types: unquote(integration_types_ast),
        contexts: unquote(contexts_ast)
      }

      def unquote(func_name)(var!(ctx)) do
        _ = var!(ctx)
        unquote(body)
      end
    end
  end

  defmacro user_command(name, do: body) do
    func_name = :"__cmd_#{name}__"

    quote do
      @lingo_commands %Lingo.Type.ApplicationCommand{
        name: unquote(name),
        description: "",
        type: :user,
        options: []
      }

      def unquote(func_name)(var!(ctx)) do
        _ = var!(ctx)
        unquote(body)
      end
    end
  end

  defmacro message_command(name, do: body) do
    func_name = :"__cmd_#{name}__"

    quote do
      @lingo_commands %Lingo.Type.ApplicationCommand{
        name: unquote(name),
        description: "",
        type: :message,
        options: []
      }

      def unquote(func_name)(var!(ctx)) do
        _ = var!(ctx)
        unquote(body)
      end
    end
  end

  defmacro handle(event_name, var, do: body) do
    func_name = :"__evt_#{event_name}__"

    quote do
      @lingo_handlers unquote(event_name)

      def unquote(func_name)(unquote(var)) do
        unquote(body)
      end
    end
  end

  defmacro autocomplete(command_name, var, do: body) do
    func_name = :"__ac_#{command_name}__"

    quote do
      @lingo_autocompletes unquote(command_name)

      def unquote(func_name)(unquote(var)) do
        unquote(body)
      end
    end
  end

  defmacro component(custom_id, var, do: body) do
    safe = sanitize_name(custom_id)
    func_name = :"__comp_#{safe}__"

    quote do
      @lingo_components unquote(custom_id)

      def unquote(func_name)(unquote(var)) do
        unquote(body)
      end
    end
  end

  defmacro modal(custom_id, var, do: body) do
    safe = sanitize_name(custom_id)
    func_name = :"__modal_#{safe}__"

    quote do
      @lingo_modals unquote(custom_id)

      def unquote(func_name)(unquote(var)) do
        unquote(body)
      end
    end
  end

  defmacro __before_compile__(env) do
    commands = Module.get_attribute(env.module, :lingo_commands) |> Enum.reverse()
    handlers = Module.get_attribute(env.module, :lingo_handlers) |> Enum.reverse() |> Enum.uniq()

    autocompletes =
      Module.get_attribute(env.module, :lingo_autocompletes) |> Enum.reverse() |> Enum.uniq()

    components =
      Module.get_attribute(env.module, :lingo_components) |> Enum.reverse() |> Enum.uniq()

    modals =
      Module.get_attribute(env.module, :lingo_modals) |> Enum.reverse() |> Enum.uniq()

    command_clauses =
      for cmd <- commands do
        name = cmd.name
        func_name = :"__cmd_#{name}__"

        quote do
          def __handle_command__(unquote(name), ctx), do: unquote(func_name)(ctx)
        end
      end

    handler_clauses =
      for event <- handlers do
        func_name = :"__evt_#{event}__"

        quote do
          def __handle_event__(unquote(event), data), do: unquote(func_name)(data)
        end
      end

    autocomplete_clauses =
      for cmd_name <- autocompletes do
        func_name = :"__ac_#{cmd_name}__"

        quote do
          def __handle_autocomplete__(unquote(cmd_name), ctx), do: unquote(func_name)(ctx)
        end
      end

    component_clauses =
      for custom_id <- components do
        safe = sanitize_name(custom_id)
        func_name = :"__comp_#{safe}__"

        quote do
          def __handle_component__(unquote(custom_id), ctx), do: unquote(func_name)(ctx)
        end
      end

    component_block =
      if components != [] do
        quote do
          unquote_splicing(component_clauses)
          def __handle_component__(_custom_id, _ctx), do: :ok
        end
      end

    modal_clauses =
      for custom_id <- modals do
        safe = sanitize_name(custom_id)
        func_name = :"__modal_#{safe}__"

        quote do
          def __handle_modal__(unquote(custom_id), ctx), do: unquote(func_name)(ctx)
        end
      end

    modal_block =
      if modals != [] do
        quote do
          unquote_splicing(modal_clauses)
          def __handle_modal__(_custom_id, _ctx), do: :ok
        end
      end

    quote do
      def __commands__, do: unquote(Macro.escape(commands))

      unquote_splicing(command_clauses)
      def __handle_command__(_name, _ctx), do: :unknown_command

      unquote_splicing(handler_clauses)
      def __handle_event__(_event, _data), do: :ok

      unquote_splicing(autocomplete_clauses)
      def __handle_autocomplete__(_name, _ctx), do: :ok

      unquote(component_block)
      unquote(modal_block)
    end
  end

  defp sanitize_name(name) when is_binary(name) do
    String.replace(name, ~r/[^a-zA-Z0-9_]/, "_")
  end

  defp sanitize_name(name), do: name
end
