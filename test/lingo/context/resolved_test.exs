defmodule Lingo.Context.ResolvedTest do
  use ExUnit.Case, async: true

  alias Lingo.Context
  alias Lingo.Type.{Channel, Interaction, Message, Role}

  describe "new/2 for context menu commands" do
    test "captures target_id for context menu commands" do
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
          "guild_id" => "g1",
          "data" => %{
            "name" => "Report User",
            "type" => 2,
            "target_id" => "target_user_123",
            "resolved" => %{
              "users" => %{
                "target_user_123" => %{
                  "id" => "target_user_123",
                  "username" => "badguy",
                  "discriminator" => "0"
                }
              }
            }
          }
        })

      ctx = Context.new(interaction)
      assert ctx.target_id == "target_user_123"
      assert ctx.command_name == "Report User"

      user = Lingo.Context.resolved_user(ctx, "target_user_123")
      assert user.username == "badguy"
    end

    test "hydrates resolved members with their resolved user and guild" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "guild_id" => "g1",
          "data" => %{
            "name" => "Inspect User",
            "options" => [%{"type" => 6, "name" => "user", "value" => "target_user_123"}],
            "resolved" => %{
              "users" => %{
                "target_user_123" => %{
                  "id" => "target_user_123",
                  "username" => "target",
                  "discriminator" => "0"
                }
              },
              "members" => %{
                "target_user_123" => %{
                  "nick" => "Target",
                  "roles" => ["role1"]
                }
              }
            }
          }
        })

      ctx = Context.new(interaction)

      assert %{guild_id: "g1", nick: "Target", user: %{id: "target_user_123"}} =
               Lingo.Context.resolved_member(ctx, "target_user_123")

      assert %{guild_id: "g1", nick: "Target", user: %{username: "target"}} =
               Lingo.Context.get_member(ctx, "user")
    end

    test "hydrates resolved role, channel, and message with context guild" do
      interaction =
        Interaction.new(%{
          "id" => "1",
          "application_id" => "2",
          "type" => 2,
          "token" => "t",
          "guild_id" => "g1",
          "data" => %{
            "name" => "Inspect Targets",
            "options" => [
              %{"type" => 8, "name" => "role", "value" => "role1"},
              %{"type" => 7, "name" => "channel", "value" => "channel1"}
            ],
            "resolved" => %{
              "roles" => %{
                "role1" => %{"id" => "role1", "name" => "Mod", "permissions" => "0"}
              },
              "channels" => %{
                "channel1" => %{"id" => "channel1", "type" => 0, "name" => "general"}
              },
              "messages" => %{
                "message1" => %{
                  "id" => "message1",
                  "channel_id" => "channel1",
                  "content" => "target"
                }
              }
            }
          }
        })

      ctx = Context.new(interaction)

      assert %Role{id: "role1", guild_id: "g1"} = Lingo.Context.get_role(ctx, "role")

      assert %Channel{id: "channel1", guild_id: "g1"} =
               Lingo.Context.get_channel(ctx, "channel")

      assert %Message{id: "message1", guild_id: "g1"} =
               Lingo.Context.resolved_message(ctx, "message1")
    end
  end
end
