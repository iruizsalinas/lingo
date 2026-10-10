defmodule Lingo.Type.EmbedTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.Embed

  describe "Embed" do
    test "to_map strips nil values" do
      embed = %Embed{title: "Hello", description: "World", color: 0xFF0000}
      map = Embed.to_map(embed)
      assert map.title == "Hello"
      assert map.color == 0xFF0000
      refute Map.has_key?(map, :url)
      refute Map.has_key?(map, :timestamp)
      refute Map.has_key?(map, :components)
    end

    test "component embeds keep their components and flags" do
      container = %{"type" => 17, "components" => [%{"type" => 10, "content" => "Hi"}]}
      embed = Embed.new(%{"type" => "components", "components" => [container], "flags" => 32})
      assert embed.components == [container]
      assert embed.flags == 32
    end
  end
end
