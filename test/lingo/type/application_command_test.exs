defmodule Lingo.Type.ApplicationCommandTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.{ApplicationCommand, CommandOption}

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

    test "attachment options preserve file type filters" do
      option = %CommandOption{
        type: :attachment,
        name: "document",
        description: "A document",
        file_types: [".pdf", "image"]
      }

      assert CommandOption.to_payload(option)["file_types"] == [".pdf", "image"]

      parsed = CommandOption.new(%{"type" => 11, "name" => "document", "file_types" => ["audio"]})
      assert parsed.file_types == ["audio"]
    end

    test "to_payload omits nil optional fields" do
      cmd = %ApplicationCommand{name: "simple", description: "Desc"}
      payload = ApplicationCommand.to_payload(cmd)
      refute Map.has_key?(payload, "default_member_permissions")
      refute Map.has_key?(payload, "nsfw")
    end

    test "to_payload omits chat-input-only fields for context menus" do
      user_payload =
        ApplicationCommand.to_payload(%ApplicationCommand{
          name: "Inspect User",
          type: :user,
          description: "",
          options: [%CommandOption{type: :string, name: "ignored", description: "ignored"}]
        })

      assert user_payload["name"] == "Inspect User"
      assert user_payload["type"] == 2
      refute Map.has_key?(user_payload, "description")
      refute Map.has_key?(user_payload, "options")

      message_payload =
        ApplicationCommand.to_payload(%ApplicationCommand{
          name: "Inspect Message",
          type: :message,
          description: ""
        })

      assert message_payload["type"] == 3
      refute Map.has_key?(message_payload, "description")
      refute Map.has_key?(message_payload, "options")
    end

    test "to_payload includes primary entry point handler" do
      payload =
        ApplicationCommand.to_payload(%ApplicationCommand{
          name: "Play",
          type: :primary_entry_point,
          handler: 2
        })

      assert payload["type"] == 4
      assert payload["handler"] == 2
      refute Map.has_key?(payload, "description")
      refute Map.has_key?(payload, "options")
    end

    test "to_payload omits handler for non-primary-entry-point commands" do
      payload =
        ApplicationCommand.to_payload(%ApplicationCommand{
          name: "test",
          description: "test",
          type: :chat_input,
          handler: 2
        })

      refute Map.has_key?(payload, "handler")
    end
  end

  describe "ApplicationCommand payloads" do
    test "integer default_member_permissions are sent as a string" do
      cmd = %ApplicationCommand{name: "ban", description: "Ban", default_member_permissions: 4}
      assert ApplicationCommand.to_payload(cmd)["default_member_permissions"] == "4"
    end
  end
end
