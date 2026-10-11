defmodule Lingo.Api.GuildTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1]

  alias Lingo.Api.Guild
  alias Lingo.Type.{GuildWidget, Invite, Onboarding, VoiceRegion, WelcomeScreen}

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  test "voice regions" do
    respond([%{"id" => "vip", "name" => "VIP", "custom" => true}])
    assert {:ok, [%VoiceRegion{id: "vip", custom: true}]} = Guild.list_voice_regions("g1")
    assert_received {:request, :get, "/api/v10/guilds/g1/regions", [], nil}
  end

  test "widget settings and the public widget" do
    respond(%{"enabled" => true, "channel_id" => "41771983444115456"})

    assert {:ok, %{enabled: true, channel_id: "41771983444115456"}} =
             Guild.get_widget_settings("g1")

    assert_received {:request, :get, "/api/v10/guilds/g1/widget", [], nil}

    assert {:ok, %{enabled: true}} = Guild.update_widget("g1", enabled: true)
    assert_received {:request, :patch, "/api/v10/guilds/g1/widget", [], %{"enabled" => true}}

    respond(%{
      "id" => "g1",
      "name" => "G",
      "channels" => [],
      "members" => [],
      "presence_count" => 3
    })

    assert {:ok, %GuildWidget{id: "g1", presence_count: 3}} = Guild.get_widget("g1")
    assert_received {:request, :get, "/api/v10/guilds/g1/widget.json", [], nil}
  end

  test "the vanity url is a partial invite" do
    respond(%{"code" => "abc", "uses" => 12})
    assert {:ok, %Invite{code: "abc", uses: 12}} = Guild.get_vanity_url("g1")
    assert_received {:request, :get, "/api/v10/guilds/g1/vanity-url", [], nil}
  end

  test "welcome screen and onboarding" do
    respond(%{"description" => "Hi", "welcome_channels" => []})
    assert {:ok, %WelcomeScreen{description: "Hi"}} = Guild.get_welcome_screen("g1")
    assert_received {:request, :get, "/api/v10/guilds/g1/welcome-screen", [], nil}

    assert {:ok, %WelcomeScreen{}} = Guild.update_welcome_screen("g1", description: "Hi")

    assert_received {:request, :patch, "/api/v10/guilds/g1/welcome-screen", [],
                     %{"description" => "Hi"}}

    respond(%{"guild_id" => "g1", "prompts" => [], "enabled" => true, "mode" => 1})
    assert {:ok, %Onboarding{guild_id: "g1", mode: :advanced}} = Guild.get_onboarding("g1")
    assert_received {:request, :get, "/api/v10/guilds/g1/onboarding", [], nil}

    assert {:ok, %Onboarding{}} = Guild.update_onboarding("g1", enabled: true)
    assert_received {:request, :put, "/api/v10/guilds/g1/onboarding", [], %{"enabled" => true}}
  end

  test "prunes return how many members they remove" do
    respond(%{"pruned" => 4})

    assert {:ok, 4} = Guild.get_prune_count("g1", days: 30, include_roles: ["r1", "r2"])

    assert_received {:request, :get, "/api/v10/guilds/g1/prune", query, nil}
    assert Enum.sort(query) == [{"days", "30"}, {"include_roles", "r1,r2"}]

    assert {:ok, 4} = Guild.begin_prune("g1", %{days: 7})
    assert_received {:request, :post, "/api/v10/guilds/g1/prune", [], %{"days" => 7}}

    respond(%{"pruned" => nil})
    assert {:ok, nil} = Guild.begin_prune("g1", compute_prune_count: false)
  end
end
