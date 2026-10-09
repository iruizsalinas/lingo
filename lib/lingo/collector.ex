defmodule Lingo.Collector do
  @moduledoc false

  @registry Lingo.Collector.Registry

  # Public API

  def await_component(message_id, opts \\ []) do
    filter = Keyword.get(opts, :filter, fn _ -> true end)
    timeout = Keyword.get(opts, :timeout, 60_000)

    await({:component, message_id}, filter, timeout)
  end

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
    {:ok, _} = Registry.register(@registry, key, {:await, filter, ref, claim})

    result =
      receive do
        {:lingo_collector, ^ref, data} -> {:ok, data}
      after
        timeout ->
          if claim(claim) do
            :timeout
          else
            # a dispatcher claimed us first, its message is on the way
            receive do
              {:lingo_collector, ^ref, data} -> {:ok, data}
            end
          end
      end

    Registry.unregister(@registry, key)
    result
  end

  def collect_reactions(channel_id, message_id, opts \\ []) do
    filter = Keyword.get(opts, :filter, fn _ -> true end)
    timeout = Keyword.fetch!(opts, :timeout)

    combined_filter = fn event ->
      event.channel_id == channel_id and filter.(event)
    end

    key = {:reaction, message_id}
    ref = make_ref()
    {:ok, _} = Registry.register(@registry, key, {:collect, combined_filter, ref})

    events = collect_loop(ref, timeout, [])
    Registry.unregister(@registry, key)
    {:ok, Enum.reverse(events)}
  end

  # Called by Dispatcher before dispatch_to_bot

  def try_match(
        :interaction_create,
        %{type: :message_component, message: %{id: msg_id}} = interaction
      )
      when is_binary(msg_id) do
    match_key({:component, msg_id}, interaction)
  end

  def try_match(:message_reaction_add, %{message_id: msg_id} = reaction)
      when is_binary(msg_id) do
    # notify collectors but don't consume, reactions still go to the bot handler
    match_key({:reaction, msg_id}, reaction)
    :miss
  end

  def try_match(_event, _data), do: :miss

  # Internal

  defp match_key(key, data) do
    case Registry.lookup(@registry, key) do
      [] ->
        :miss

      entries ->
        matched_await =
          Enum.reduce(entries, false, fn
            {pid, {:await, filter, ref, claim}}, found ->
              if safe_filter(filter, data) and claim(claim) do
                send(pid, {:lingo_collector, ref, data})
                true
              else
                found
              end

            {pid, {:collect, filter, ref}}, found ->
              if safe_filter(filter, data), do: send(pid, {:lingo_collector, ref, data})
              found
          end)

        case key do
          {:component, _} when matched_await -> :collected
          _ -> :miss
        end
    end
  end

  defp claim(claim), do: :atomics.compare_exchange(claim, 1, 0, 1) == :ok

  defp safe_filter(filter, data) do
    filter.(data)
  rescue
    _ -> false
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
