defmodule Lingo.TypeTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{
    ApplicationCommand,
    Channel,
    CommandOption,
    Component,
    Embed,
    Emoji,
    Guild,
    Interaction,
    Message,
    User
  }

  describe "User" do
    test "parses all fields" do
      data = %{
        "id" => "12345",
        "username" => "testuser",
        "discriminator" => "0",
        "global_name" => "Test User",
        "avatar" => "abc123",
        "bot" => true,
        "public_flags" => 256
      }

      user = User.new(data)
      assert user.id == "12345"
      assert user.username == "testuser"
      assert user.global_name == "Test User"
      assert user.avatar == "abc123"
      assert user.bot == true
      assert user.public_flags == 256
    end

    test "defaults bot to false" do
      user = User.new(%{"id" => "1", "username" => "u", "discriminator" => "0"})
      assert user.bot == false
    end

    test "returns nil for nil" do
      assert User.new(nil) == nil
    end
  end

  describe "Guild" do
    test "parses enum fields to atoms" do
      data = %{
        "id" => "1",
        "name" => "Test",
        "owner_id" => "2",
        "verification_level" => 0,
        "default_message_notifications" => 1,
        "explicit_content_filter" => 2,
        "mfa_level" => 1,
        "nsfw_level" => 3,
        "premium_tier" => 2
      }

      guild = Guild.new(data)
      assert guild.verification_level == :none
      assert guild.default_message_notifications == :only_mentions
      assert guild.explicit_content_filter == :all_members
      assert guild.mfa_level == :elevated
      assert guild.nsfw_level == :age_restricted
      assert guild.premium_tier == :tier_2
    end

    test "parses nested roles and emojis" do
      data = %{
        "id" => "1",
        "name" => "G",
        "owner_id" => "2",
        "roles" => [
          %{"id" => "r1", "name" => "Admin", "permissions" => "8"},
          %{"id" => "r2", "name" => "Member", "permissions" => "0"}
        ],
        "emojis" => [
          %{"id" => "e1", "name" => "happy", "animated" => true}
        ]
      }

      guild = Guild.new(data)
      assert length(guild.roles) == 2
      assert hd(guild.roles).name == "Admin"
      assert length(guild.emojis) == 1
      assert hd(guild.emojis).animated == true
    end

    test "handles unavailable guild" do
      guild = Guild.new(%{"id" => "1", "unavailable" => true})
      assert guild.unavailable == true
      assert guild.name == nil
    end
  end

  describe "Channel" do
    test "maps type integers to atoms" do
      types = %{
        0 => :guild_text,
        1 => :dm,
        2 => :guild_voice,
        4 => :guild_category,
        5 => :guild_announcement,
        11 => :public_thread,
        12 => :private_thread,
        13 => :guild_stage_voice,
        15 => :guild_forum
      }

      for {int, atom} <- types do
        channel = Channel.new(%{"id" => "1", "type" => int})
        assert channel.type == atom, "Expected type #{int} to map to #{atom}, got #{channel.type}"
      end
    end

    test "parses permission overwrites" do
      data = %{
        "id" => "1",
        "type" => 0,
        "permission_overwrites" => [
          %{"id" => "r1", "type" => 0, "allow" => "1024", "deny" => "0"},
          %{"id" => "u1", "type" => 1, "allow" => "0", "deny" => "2048"}
        ]
      }

      channel = Channel.new(data)
      assert length(channel.permission_overwrites) == 2
      [role_ow, member_ow] = channel.permission_overwrites
      assert role_ow.type == :role
      assert member_ow.type == :member
      assert role_ow.allow == "1024"
    end
  end

  describe "Message" do
    test "parses nested author and member" do
      data = %{
        "id" => "m1",
        "channel_id" => "c1",
        "author" => %{"id" => "u1", "username" => "sender", "discriminator" => "0"},
        "member" => %{"nick" => "Snd", "roles" => ["r1"]},
        "content" => "hello world",
        "timestamp" => "2024-01-01T00:00:00Z",
        "embeds" => [%{"title" => "Test"}],
        "attachments" => [
          %{
            "id" => "a1",
            "filename" => "img.png",
            "size" => 1024,
            "url" => "https://cdn/img.png",
            "proxy_url" => "https://proxy/img.png"
          }
        ],
        "reactions" => [%{"count" => 3, "emoji" => %{"name" => "👍"}}]
      }

      msg = Message.new(data)
      assert msg.content == "hello world"
      assert msg.author.username == "sender"
      assert msg.member.nick == "Snd"
      assert length(msg.embeds) == 1
      assert hd(msg.embeds).title == "Test"
      assert hd(msg.attachments).filename == "img.png"
      assert hd(msg.reactions).count == 3
    end

    test "referenced_message recursion" do
      data = %{
        "id" => "m2",
        "channel_id" => "c1",
        "content" => "reply",
        "timestamp" => "2024-01-01T00:00:00Z",
        "referenced_message" => %{
          "id" => "m1",
          "channel_id" => "c1",
          "content" => "original",
          "timestamp" => "2024-01-01T00:00:00Z"
        }
      }

      msg = Message.new(data)
      assert msg.referenced_message.content == "original"
    end
  end

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
  end

  describe "ApplicationCommand" do
    test "to_payload serializes correctly" do
      cmd = %ApplicationCommand{
        name: "test",
        description: "A test command",
        type: :chat_input,
        options: [
          %CommandOption{type: :string, name: "arg", description: "An arg", required: true},
          %CommandOption{type: :user, name: "target", description: "A target"}
        ]
      }

      payload = ApplicationCommand.to_payload(cmd)
      assert payload["name"] == "test"
      assert payload["description"] == "A test command"
      assert payload["type"] == 1
      assert length(payload["options"]) == 2

      [arg, target] = payload["options"]
      assert arg["type"] == 3
      assert arg["required"] == true
      assert target["type"] == 6
      assert target["required"] == false
    end

    test "to_payload omits nil optional fields" do
      cmd = %ApplicationCommand{name: "simple", description: "Desc"}
      payload = ApplicationCommand.to_payload(cmd)
      refute Map.has_key?(payload, "default_member_permissions")
      refute Map.has_key?(payload, "nsfw")
    end
  end

  describe "Embed" do
    test "to_map strips nil values" do
      embed = %Embed{title: "Hello", description: "World", color: 0xFF0000}
      map = Embed.to_map(embed)
      assert map.title == "Hello"
      assert map.color == 0xFF0000
      refute Map.has_key?(map, :url)
      refute Map.has_key?(map, :timestamp)
    end
  end

  describe "Emoji" do
    test "format for unicode emoji" do
      emoji = %Emoji{id: nil, name: "👍"}
      assert Emoji.format(emoji) == "👍"
    end

    test "format for custom emoji" do
      emoji = %Emoji{id: "123", name: "custom"}
      assert Emoji.format(emoji) == "<:custom:123>"
    end

    test "format for animated custom emoji" do
      emoji = %Emoji{id: "456", name: "dance", animated: true}
      assert Emoji.format(emoji) == "<a:dance:456>"
    end
  end

  describe "Component" do
    test "action_row builder returns a ready-to-use map" do
      row =
        Component.action_row([
          Component.button(custom_id: "btn1", label: "Click", style: :primary)
        ])

      assert row.type == 1
      assert length(row.components) == 1
      assert hd(row.components).label == "Click"
    end

    test "button builder returns encoded map" do
      btn = Component.button(custom_id: "x", label: "X", style: :danger)
      assert btn.type == 2
      assert btn.style == 4
      assert btn.label == "X"
      assert btn.custom_id == "x"
    end

    test "button premium style with sku_id" do
      btn = Component.button(style: :premium, sku_id: "sku_123")
      assert btn.type == 2
      assert btn.style == 6
      assert btn.sku_id == "sku_123"
      refute Map.has_key?(btn, :custom_id)
    end

    test "components_v2_flag returns correct value" do
      assert Component.components_v2_flag() == 32768
    end

    test "user_select builder" do
      sel = Component.user_select("pick_user", placeholder: "Choose a user", max_values: 3)
      assert sel.type == 5
      assert sel.custom_id == "pick_user"
      assert sel.placeholder == "Choose a user"
      assert sel.max_values == 3
    end

    test "role_select builder" do
      sel = Component.role_select("pick_role")
      assert sel.type == 6
      assert sel.custom_id == "pick_role"
    end

    test "mentionable_select builder" do
      sel = Component.mentionable_select("pick_any", min_values: 1, max_values: 5)
      assert sel.type == 7
      assert sel.min_values == 1
      assert sel.max_values == 5
    end

    test "channel_select with channel_types" do
      sel = Component.channel_select("pick_ch", channel_types: [0, 2])
      assert sel.type == 8
      assert sel.channel_types == [0, 2]
    end

    test "select with default_values" do
      sel =
        Component.user_select("sel",
          default_values: [Component.default_value("123", "user")]
        )

      assert [%{id: "123", type: "user"}] = sel.default_values
    end

    test "text_display builder" do
      td = Component.text_display("**bold** text")
      assert td.type == 10
      assert td.content == "**bold** text"
    end

    test "section builder" do
      sec =
        Component.section(
          [Component.text_display("hello")],
          Component.thumbnail("https://example.com/img.png")
        )

      assert sec.type == 9
      assert length(sec.components) == 1
      assert sec.accessory.type == 11
    end

    test "thumbnail builder" do
      th = Component.thumbnail("https://example.com/img.png", description: "alt text")
      assert th.type == 11
      assert th.media == %{url: "https://example.com/img.png"}
      assert th.description == "alt text"
    end

    test "media_gallery builder" do
      gallery =
        Component.media_gallery([
          Component.gallery_item("https://example.com/a.png"),
          Component.gallery_item("https://example.com/b.png", description: "B", spoiler: true)
        ])

      assert gallery.type == 12
      assert length(gallery.items) == 2
      assert Enum.at(gallery.items, 1).spoiler == true
    end

    test "file builder" do
      f = Component.file("attachment://image.png", spoiler: true)
      assert f.type == 13
      assert f.file == %{url: "attachment://image.png"}
      assert f.spoiler == true
    end

    test "separator builder defaults" do
      sep = Component.separator()
      assert sep.type == 14
      refute Map.has_key?(sep, :divider)
      refute Map.has_key?(sep, :spacing)
    end

    test "separator with divider false and large spacing" do
      sep = Component.separator(divider: false, spacing: :large)
      assert sep.type == 14
      assert sep.divider == false
      assert sep.spacing == 2
    end

    test "container builder" do
      c =
        Component.container(
          [Component.text_display("inside")],
          accent_color: 0xFF0000,
          spoiler: true
        )

      assert c.type == 17
      assert length(c.components) == 1
      assert c.accent_color == 0xFF0000
      assert c.spoiler == true
    end

    test "label builder" do
      l =
        Component.label(
          "Your name",
          Component.text_input("name", "Name"),
          description: "Enter your full name"
        )

      assert l.type == 18
      assert l.label == "Your name"
      assert l.component.type == 4
      assert l.description == "Enter your full name"
    end

    test "file_upload builder" do
      fu = Component.file_upload("upload", max_values: 5)
      assert fu.type == 19
      assert fu.custom_id == "upload"
      assert fu.max_values == 5
    end

    test "radio_group builder" do
      rg =
        Component.radio_group("color", [
          Component.select_option("Red", "red"),
          Component.select_option("Blue", "blue")
        ])

      assert rg.type == 21
      assert length(rg.options) == 2
    end

    test "checkbox_group builder" do
      cg =
        Component.checkbox_group(
          "toppings",
          [
            Component.select_option("Cheese", "cheese"),
            Component.select_option("Peppers", "peppers", default: true)
          ],
          min_values: 1
        )

      assert cg.type == 22
      assert cg.min_values == 1
      assert Enum.at(cg.options, 1).default == true
    end

    test "checkbox builder" do
      cb = Component.checkbox("agree", default: true)
      assert cb.type == 23
      assert cb.custom_id == "agree"
      assert cb.default == true
    end

    test "checkbox with default false is preserved" do
      cb = Component.checkbox("tos", default: false)
      assert cb.default == false
    end

    test "modal builder" do
      m =
        Component.modal("my_modal", "Feedback", [
          Component.label("Comment", Component.text_input("comment", "Comment"))
        ])

      assert m.custom_id == "my_modal"
      assert m.title == "Feedback"
      assert length(m.components) == 1
    end

    test "gallery_item helper" do
      gi = Component.gallery_item("https://example.com/pic.png", description: "A pic")
      assert gi.media == %{url: "https://example.com/pic.png"}
      assert gi.description == "A pic"
    end

    test "unfurled_media helper" do
      um = Component.unfurled_media("https://example.com/img.png")
      assert um == %{url: "https://example.com/img.png"}
    end

    test "select_option helper" do
      so = Component.select_option("Red", "red", description: "The color red")
      assert so.label == "Red"
      assert so.value == "red"
      assert so.description == "The color red"
    end

    test "default_value helper" do
      dv = Component.default_value("123456", "user")
      assert dv == %{id: "123456", type: "user"}
    end

    test "builders produce JSON-safe maps" do
      row =
        Component.action_row([
          Component.button(custom_id: "a", label: "A", style: :success)
        ])

      assert {:ok, _} = Jason.encode(row)
    end

    test "V2 composition encodes to JSON" do
      payload =
        Component.container(
          [
            Component.text_display("Welcome!"),
            Component.separator(spacing: :large),
            Component.section(
              [Component.text_display("Click the button")],
              Component.button(custom_id: "go", label: "Go", style: :primary)
            ),
            Component.media_gallery([
              Component.gallery_item("https://example.com/a.png")
            ]),
            Component.action_row([
              Component.button(custom_id: "ok", label: "OK", style: :success)
            ])
          ],
          accent_color: 0x5865F2
        )

      assert {:ok, json} = Jason.encode(payload)
      assert is_binary(json)
    end
  end
end
