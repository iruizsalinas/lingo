defmodule Lingo.Type.ApplicationTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{Application, User}

  # Discord's example application object
  @example ~S"""
  {
    "bot_public": true,
    "bot_require_code_grant": false,
    "cover_image": "31deabb7e45b6c8ecfef77d2f99c81a5",
    "description": "Test",
    "flags": 8192,
    "flags_new": "8192",
    "guild_id": "290926798626357260",
    "icon": null,
    "id": "172150183260323840",
    "integration_types_config": {
      "0": {
        "oauth2_install_params": {
          "scopes": ["applications.commands", "bot"],
          "permissions": "2048"
        }
      },
      "1": {
        "oauth2_install_params": {"scopes": ["applications.commands"], "permissions": "0"}
      }
    },
    "name": "Baba O-Riley",
    "interactions_endpoint_url": null,
    "role_connections_verification_url": null,
    "event_webhooks_url": null,
    "event_webhooks_status": 1,
    "owner": {
      "avatar": null,
      "discriminator": "1738",
      "flags": 1024,
      "id": "172150183260323840",
      "username": "i own a bot"
    },
    "primary_sku_id": "172150183260323840",
    "slug": "test",
    "team": {
      "name": "A team",
      "icon": "dd9b7dcfdf5351b9c3de0fe167bacbe1",
      "id": "531992624043786253",
      "owner_user_id": "511972282709709995",
      "members": [
        {
          "membership_state": 2,
          "permissions": ["*"],
          "team_id": "531992624043786253",
          "user": {
            "avatar": "d9e261cd35999608eb7e3de1fae3688b",
            "discriminator": "0001",
            "id": "511972282709709995",
            "username": "Mr Owner"
          }
        }
      ]
    },
    "verify_key": "1e0a356058d627ca38a5c8c9648818061d49e49bd9da9e3ab17d98ad4d6bg2u8"
  }
  """

  test "parses Discord's example application" do
    app = Application.new(JSON.decode!(@example))

    assert %Application{
             id: "172150183260323840",
             name: "Baba O-Riley",
             description: "Test",
             icon: nil,
             bot_public: true,
             bot_require_code_grant: false,
             flags: 8192,
             flags_new: "8192",
             guild_id: "290926798626357260",
             primary_sku_id: "172150183260323840",
             slug: "test",
             event_webhooks_status: :disabled,
             owner: %User{id: "172150183260323840", username: "i own a bot"}
           } = app

    assert app.integration_types_config == %{
             guild: %{
               oauth2_install_params: %{
                 scopes: ["applications.commands", "bot"],
                 permissions: "2048"
               }
             },
             user: %{
               oauth2_install_params: %{scopes: ["applications.commands"], permissions: "0"}
             }
           }

    assert %{
             id: "531992624043786253",
             name: "A team",
             owner_user_id: "511972282709709995",
             members: [member]
           } = app.team

    assert %{membership_state: :accepted, role: nil, user: %User{username: "Mr Owner"}} = member
  end

  test "partial applications, as in messages, keep the defaults" do
    assert %Application{
             id: "1",
             name: "Game",
             team: nil,
             install_params: nil,
             integration_types_config: nil,
             tags: [],
             redirect_uris: []
           } = Application.new(%{"id" => "1", "name" => "Game"})
  end

  test "unknown codes and integration types pass through" do
    app =
      Application.new(%{
        "event_webhooks_status" => 9,
        "install_params" => %{"scopes" => ["bot"], "permissions" => "8"},
        "integration_types_config" => %{"5" => %{}},
        "team" => %{"members" => [%{"membership_state" => 7, "role" => "developer"}]}
      })

    assert app.event_webhooks_status == 9
    assert app.install_params == %{scopes: ["bot"], permissions: "8"}
    assert app.integration_types_config == %{"5" => %{oauth2_install_params: nil}}
    assert [%{membership_state: 7, role: "developer", user: nil}] = app.team.members
  end
end
