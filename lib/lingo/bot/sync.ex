defmodule Lingo.Bot.Sync do
  @moduledoc false

  require Logger

  alias Lingo.Api.Command
  alias Lingo.Instance
  alias Lingo.Type.ApplicationCommand

  @type scope :: :global | {:guild, String.t()} | {:guilds, [String.t()]}

  @spec register(scope()) :: {:ok, [map()]} | {:error, Lingo.Error.t()}
  def register(scope \\ :global) do
    payloads = Enum.map(commands(), &ApplicationCommand.to_payload/1)

    case scope do
      :global ->
        Command.bulk_overwrite_global(payloads)

      {:guild, guild_id} ->
        Command.bulk_overwrite_guild(guild_id, payloads)

      {:guilds, guild_ids} ->
        Enum.reduce_while(guild_ids, {:ok, []}, fn guild_id, {:ok, acc} ->
          case Command.bulk_overwrite_guild(guild_id, payloads) do
            {:ok, registered} -> {:cont, {:ok, acc ++ registered}}
            error -> {:halt, error}
          end
        end)
    end
  end

  # runs once every shard is ready, when the bot was started with :register_commands
  @spec register_on_ready() :: :ok
  def register_on_ready do
    case Instance.get(:register_commands) do
      scope when scope in [nil, false] ->
        :ok

      scope ->
        bot = Instance.current()

        Task.Supervisor.start_child(Instance.process_name(bot, Lingo.TaskSupervisor), fn ->
          Instance.put_current(bot)

          case register(scope) do
            {:ok, _commands} ->
              :ok

            {:error, error} ->
              Logger.error("Lingo could not register commands: #{Exception.message(error)}")
          end
        end)

        :ok
    end
  end

  defp commands do
    bot = Instance.get(:bot)
    if bot && function_exported?(bot, :__commands__, 0), do: bot.__commands__(), else: []
  end
end
