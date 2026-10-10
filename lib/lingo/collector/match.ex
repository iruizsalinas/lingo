defmodule Lingo.Collector.Match do
  @moduledoc false

  # The dispatcher side of collectors: hands events to the processes waiting
  # for them. A matched component awaiter consumes its interaction.

  defp registry, do: Lingo.Instance.process_name(Lingo.Collector.Registry)

  @doc false
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

  def match_key(key, data) do
    case Registry.lookup(registry(), key) do
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

  def claim(claim), do: :atomics.compare_exchange(claim, 1, 0, 1) == :ok

  def safe_filter(filter, data) do
    filter.(data)
  rescue
    _ -> false
  end
end
