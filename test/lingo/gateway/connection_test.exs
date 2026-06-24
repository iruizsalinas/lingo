defmodule Lingo.Gateway.ConnectionTest do
  use ExUnit.Case

  alias Lingo.Gateway.Connection

  defmodule EventBot do
    use Lingo.Bot

    handle :rate_limited, data do
      send(:persistent_term.get({:lingo_test, :connection_parent}), {:rate_limited, data})
    end
  end

  setup do
    previous_bot = Lingo.Config.bot_module()

    :persistent_term.put({:lingo_test, :connection_parent}, self())
    Lingo.Config.put(:bot_module, EventBot)

    on_exit(fn ->
      Lingo.Config.put(:bot_module, previous_bot)
      :persistent_term.erase({:lingo_test, :connection_parent})
    end)
  end

  test "maps RATE_LIMITED dispatches to rate_limited events" do
    payload =
      Jason.encode!(%{
        "op" => 0,
        "t" => "RATE_LIMITED",
        "s" => 12,
        "d" => %{
          "opcode" => 8,
          "retry_after" => 60.0,
          "meta" => %{"guild_id" => "guild1", "nonce" => "nonce1"}
        }
      })

    state = %Connection{gun_pid: self(), stream_ref: :stream, seq: 11}

    assert {:noreply, %Connection{seq: 12}} =
             Connection.handle_info({:gun_ws, self(), :stream, {:text, payload}}, state)

    assert_receive {:rate_limited,
                    %{
                      "opcode" => 8,
                      "retry_after" => 60.0,
                      "meta" => %{"guild_id" => "guild1", "nonce" => "nonce1"}
                    }}
  end
end
