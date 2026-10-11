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

    test "parses the partial guild and channel and the entitlements" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "guild_id" => "60",
          "guild" => %{"id" => "60", "locale" => "fr", "features" => ["COMMUNITY"]},
          "channel" => %{"id" => "50", "type" => 0, "nsfw" => true, "name" => "general"},
          "entitlements" => [%{"id" => "e1", "sku_id" => "s1", "type" => 8}]
        })

      assert %Lingo.Type.Guild{id: "60", preferred_locale: "fr", features: ["COMMUNITY"]} =
               interaction.guild

      assert %Lingo.Type.Channel{id: "50", guild_id: "60", type: :guild_text, nsfw: true} =
               interaction.channel

      assert [%Lingo.Type.Entitlement{id: "e1", type: :application_subscription}] =
               interaction.entitlements

      assert interaction.channel_id == "50"
    end

    test "a DM has no guild, and its channel no guild id" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "type" => 2,
          "token" => "t",
          "channel" => %{"id" => "50", "type" => 1}
        })

      assert interaction.guild == nil
      assert %Lingo.Type.Channel{type: :dm, guild_id: nil} = interaction.channel
      assert interaction.entitlements == []
    end
  end
end
