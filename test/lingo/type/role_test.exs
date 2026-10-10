defmodule Lingo.Type.RoleTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.Role

  describe "Role" do
    test "parses role colors object" do
      role =
        Role.new(%{
          "id" => "role1",
          "guild_id" => "guild1",
          "name" => "Gradient",
          "color" => 3_447_003,
          "colors" => %{
            "primary_color" => 3_447_003,
            "secondary_color" => 16_759_788,
            "tertiary_color" => nil
          },
          "permissions" => "0"
        })

      assert role.guild_id == "guild1"
      assert role.color == 3_447_003
      assert role.colors["primary_color"] == 3_447_003
      assert role.colors["secondary_color"] == 16_759_788
      assert role.colors["tertiary_color"] == nil
    end
  end
end
