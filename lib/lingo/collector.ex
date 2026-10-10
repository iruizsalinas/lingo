defmodule Lingo.Collector do
  @moduledoc """
  Waiting for button clicks and reactions inline, instead of in a separate
  callback.

      {:ok, message} = Lingo.Api.Message.create(channel_id, %{content: "Sure?", components: [row]})

      case Lingo.Collector.await_component(message.id, timeout: 30_000) do
        {:ok, interaction} -> ...
        :timeout -> ...
      end

  A component interaction an awaiter takes doesn't reach
  `c:Lingo.Bot.handle_component/2`. Reactions reach the bot as usual.
  """

  defp registry, do: Lingo.Instance.process_name(Lingo.Collector.Registry)

  @doc "Waits for a component interaction on a message. Options: `:filter` (a function that gets the interaction) and `:timeout` (ms, default 60000). Returns `{:ok, interaction}` or `:timeout`."
  def await_component(message_id, opts \\ []) do
    filter = Keyword.get(opts, :filter, fn _ -> true end)
    timeout = Keyword.get(opts, :timeout, 60_000)

    await({:component, message_id}, filter, timeout)
  end

  @doc "Waits for a reaction on a message. Takes the same options as `await_component/2`. Returns `{:ok, reaction_event}` or `:timeout`."
  def await_reaction(channel_id, message_id, opts \\ []) do
    filter = Keyword.get(opts, :filter, fn _ -> true end)
    timeout = Keyword.get(opts, :timeout, 60_000)

    combined_filter = fn event ->
      event.channel_id == channel_id and filter.(event)
    end

    await({:reaction, message_id}, combined_filter, timeout)
  end

  # Each awaiter can be claimed exactly once, so a second matching event (or
  # one racing the timeout) is never swallowed or left in the mailbox.
  defp await(key, filter, timeout) do
    ref = make_ref()
    claim = :atomics.new(1, [])
    {:ok, _} = Registry.register(registry(), key, {:await, filter, ref, claim})

    result =
      receive do
        {:lingo_collector, ^ref, data} -> {:ok, data}
      after
        timeout ->
          if Lingo.Collector.Match.claim(claim) do
            :timeout
          else
            # a dispatcher claimed us first, its message is on the way
            receive do
              {:lingo_collector, ^ref, data} -> {:ok, data}
            end
          end
      end

    Registry.unregister(registry(), key)
    result
  end

  @doc "Collects every reaction on a message until `:timeout` (ms, required) runs out. Takes a `:filter` too. Returns `{:ok, reaction_events}`."
  def collect_reactions(channel_id, message_id, opts \\ []) do
    filter = Keyword.get(opts, :filter, fn _ -> true end)
    timeout = Keyword.fetch!(opts, :timeout)

    combined_filter = fn event ->
      event.channel_id == channel_id and filter.(event)
    end

    key = {:reaction, message_id}
    ref = make_ref()
    {:ok, _} = Registry.register(registry(), key, {:collect, combined_filter, ref})

    events = collect_loop(ref, timeout, [])
    Registry.unregister(registry(), key)
    {:ok, Enum.reverse(events)}
  end

  defp collect_loop(_ref, remaining, acc) when remaining <= 0, do: acc

  defp collect_loop(ref, remaining, acc) do
    start = System.monotonic_time(:millisecond)

    receive do
      {:lingo_collector, ^ref, event} ->
        elapsed = System.monotonic_time(:millisecond) - start
        collect_loop(ref, remaining - elapsed, [event | acc])
    after
      remaining -> acc
    end
  end
end
