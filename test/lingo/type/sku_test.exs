defmodule Lingo.Type.SKUTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.SKU

  test "parses the type, passing unknown ones through" do
    assert %SKU{id: "1", type: :subscription, name: "Pro", slug: "pro", flags: 128} =
             SKU.new(%{
               "id" => "1",
               "type" => 5,
               "name" => "Pro",
               "slug" => "pro",
               "flags" => 128
             })

    assert %SKU{type: :subscription_group} = SKU.new(%{"id" => "1", "type" => 6})
    assert %SKU{type: 99} = SKU.new(%{"id" => "1", "type" => 99})
  end
end
