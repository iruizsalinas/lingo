defmodule Lingo.Command.Registry do
  @moduledoc false

  alias Lingo.Api.Command
  alias Lingo.Type.ApplicationCommand

  def sync(bot_module) do
    Code.ensure_loaded(bot_module)

    if function_exported?(bot_module, :__commands__, 0) do
      sync_commands(bot_module.__commands__())
    else
      {:error, :no_commands}
    end
  end

  def sync_to_guild(bot_module, guild_id) do
    Code.ensure_loaded(bot_module)

    if function_exported?(bot_module, :__commands__, 0) do
      payloads = Enum.map(bot_module.__commands__(), &ApplicationCommand.to_payload/1)
      Command.bulk_overwrite_guild(Lingo.Config.application_id(), guild_id, payloads)
    else
      {:error, :no_commands}
    end
  end

  defp sync_commands(commands) do
    app_id = Lingo.Config.application_id()
    if is_nil(app_id), do: throw({:error, :no_application_id})

    payloads = Enum.map(commands, &ApplicationCommand.to_payload/1)
    Command.bulk_overwrite_global(app_id, payloads)
  catch
    {:error, _} = err -> err
  end
end
