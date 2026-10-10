defmodule Lingo.Integration.EmojiTest do
  @moduledoc false
  use Lingo.IntegrationCase

  @test_image "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

  setup do
    guild_id = System.get_env("GUILD_ID")
    if is_nil(guild_id) or guild_id == "", do: raise("GUILD_ID not set")
    %{guild_id: guild_id}
  end

  describe "list/1" do
    test "returns a list of emojis", %{guild_id: guild_id} do
      assert {:ok, emojis} = Lingo.Api.Emoji.list(guild_id)
      assert is_list(emojis)
    end
  end

  describe "guild emoji CRUD" do
    test "create, get, modify, and delete a guild emoji", %{guild_id: guild_id} do
      name = "lingotest#{:rand.uniform(99999)}"

      {:ok, emoji} = Lingo.Api.Emoji.create(guild_id, %{name: name, image: @test_image})

      on_exit(fn -> Lingo.Api.Emoji.delete(guild_id, emoji.id) end)

      assert is_binary(emoji.id)
      assert emoji.name == name

      # get
      assert {:ok, fetched} = Lingo.Api.Emoji.get(guild_id, emoji.id)
      assert fetched.id == emoji.id
      assert fetched.name == name

      # modify
      assert {:ok, updated} = Lingo.Api.Emoji.update(guild_id, emoji.id, %{name: "lingorenamed"})
      assert updated.id == emoji.id
      assert updated.name == "lingorenamed"

      # delete
      assert :ok = Lingo.Api.Emoji.delete(guild_id, emoji.id)
      assert {:error, %Lingo.Error{status: 404}} = Lingo.Api.Emoji.get(guild_id, emoji.id)
    end
  end

  describe "application emojis" do
    test "list, create, and delete an application emoji" do
      assert {:ok, emojis} = Lingo.Api.Emoji.list_application()
      assert is_list(emojis)

      name = "lingoapptest#{:rand.uniform(99999)}"

      {:ok, emoji} =
        Lingo.Api.Emoji.create_application(%{name: name, image: @test_image})

      on_exit(fn -> Lingo.Api.Emoji.delete_application(emoji.id) end)

      assert is_binary(emoji.id)
      assert emoji.name == name

      # delete
      assert :ok = Lingo.Api.Emoji.delete_application(emoji.id)
    end
  end
end
