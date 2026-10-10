defmodule Lingo.Endpoint.Pending do
  @moduledoc false

  # Interactions received over HTTP whose request is held open until the bot
  # answers them. The interaction callback (whoever sends it, from whatever
  # process) tells the waiting request, through a per-bot registry.

  alias Lingo.Instance

  def child_spec(opts),
    do: Registry.child_spec(keys: :unique, name: name(Keyword.fetch!(opts, :bot)))

  @spec watch(term(), String.t()) :: :ok
  def watch(bot, id) do
    Registry.register(name(bot), id, nil)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec unwatch(term(), String.t()) :: :ok
  def unwatch(bot, id) do
    Registry.unregister(name(bot), id)
  rescue
    ArgumentError -> :ok
  end

  @doc "Called once an interaction's callback was sent."
  @spec answered(term(), String.t()) :: :ok
  def answered(bot, id) do
    id = to_string(id)
    for {pid, _} <- Registry.lookup(name(bot), id), do: send(pid, {__MODULE__, id})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec await(String.t(), timeout()) :: :ok | :timeout
  def await(id, timeout) do
    receive do
      {__MODULE__, ^id} -> :ok
    after
      timeout -> :timeout
    end
  end

  defp name(bot), do: Instance.process_name(bot, __MODULE__)
end
