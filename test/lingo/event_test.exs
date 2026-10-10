defmodule Lingo.EventTest do
  use ExUnit.Case, async: true

  alias Lingo.Event.Catalog
  alias Lingo.Gateway.Dispatcher

  # enough of every field Discord sends for any event to parse
  @data %{
    "id" => "1",
    "guild_id" => "2",
    "channel_id" => "3",
    "user_id" => "4",
    "message_id" => "5",
    "role_id" => "6",
    "user" => %{"id" => "4", "username" => "u"},
    "role" => %{"id" => "6", "name" => "r"},
    "emoji" => %{"name" => "x"},
    "emojis" => [%{"id" => "7", "name" => "e"}],
    "stickers" => [],
    "ids" => ["5"],
    "threads" => [%{"id" => "8", "type" => 11}],
    "members" => [%{"user" => %{"id" => "4"}}],
    "shard" => [0, 1],
    "type" => 0,
    "timestamp" => 1_700_000_000,
    "opcode" => 8,
    "retry_after" => 1.5,
    "meta" => %{"guild_id" => "2"},
    "action" => %{"type" => 1},
    "soundboard_sounds" => [%{"sound_id" => "9", "name" => "s"}],
    "channels" => [%{"id" => "3", "status" => "live"}]
  }

  setup do
    Lingo.TestBot.start(
      start: [:cache],
      cache: Enum.map(Lingo.Cache.Policy.resources(), &{&1, true})
    )

    :ok
  end

  test "every gateway event parses to the payload the catalog declares" do
    for {_type, name, payload} <- Catalog.gateway(), payload != :internal do
      assert_shape(name, payload, Dispatcher.payload(name, @data))
    end
  end

  test "every webhook event parses to the payload the catalog declares" do
    for {_type, name, payload} <- Catalog.webhook() do
      assert_shape(name, payload, Catalog.parse(name, @data))
    end
  end

  test "names are unique, and the same name means the same payload everywhere" do
    for events <- [Catalog.gateway(), Catalog.webhook()] do
      assert events |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == length(events)
      assert events |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == length(events)
    end

    for {_type, name, payload} <- Catalog.webhook(),
        gateway = List.keyfind(Catalog.gateway(), name, 1),
        do: assert(elem(gateway, 2) == payload)
  end

  test "the docs list every event the bot can get" do
    {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Lingo.Event)

    for {_type, name, payload} <- Catalog.gateway() ++ Catalog.webhook(),
        payload != :internal,
        do: assert(moduledoc =~ "| `#{inspect(name)}` |", "#{inspect(name)} is not documented")
  end

  test "unknown event types keep Discord's name" do
    assert Catalog.gateway_name("MESSAGE_CREATE") == :message_create
    assert Catalog.gateway_name("SOMETHING_NEW") == {:unknown, "SOMETHING_NEW"}
    assert Catalog.webhook_name("MESSAGE_CREATE") == {:unknown, "MESSAGE_CREATE"}

    assert %Lingo.Event.Unknown{type: "SOMETHING_NEW", data: %{"a" => 1}} =
             Catalog.parse({:unknown, "SOMETHING_NEW"}, %{"a" => 1})
  end

  defp assert_shape(name, {:update, module}, result) do
    assert %{old: old, new: %^module{}} = result, "#{inspect(name)} gave #{inspect(result)}"
    assert old == nil or is_struct(old, module)
  end

  defp assert_shape(name, module, result),
    do: assert(is_struct(result, module), "#{inspect(name)} gave #{inspect(result)}")
end
