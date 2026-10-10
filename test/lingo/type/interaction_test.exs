defmodule Lingo.Type.InteractionTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.Interaction

  describe "Interaction" do
    test "parses interaction types" do
      types = %{
        1 => :ping,
        2 => :application_command,
        3 => :message_component,
        4 => :autocomplete,
        5 => :modal_submit
      }

      for {int, atom} <- types do
        interaction =
          Interaction.new(%{"id" => "1", "application_id" => "2", "type" => int, "token" => "t"})

        assert interaction.type == atom
      end
    end

    test "author returns member user in guild context" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "member" => %{
            "user" => %{"id" => "u1", "username" => "alice", "discriminator" => "0"},
            "roles" => []
          },
          "guild_id" => "g1"
        })

      assert Interaction.author(interaction).username == "alice"
    end

    test "author returns user in DM context" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "user" => %{"id" => "u1", "username" => "bob", "discriminator" => "0"}
        })

      assert Interaction.author(interaction).username == "bob"
    end

    test "parses attachment size limit" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "attachment_size_limit" => 26_214_400
        })

      assert interaction.attachment_size_limit == 26_214_400
    end
  end
end
