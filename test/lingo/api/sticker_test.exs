defmodule Lingo.Api.StickerTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1]

  alias Lingo.Api.Sticker
  alias Lingo.Type.StickerPack

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  # Discord's example sticker pack
  @pack %{
    "id" => "847199849233514549",
    "stickers" => [%{"id" => "749053689419006003", "name" => "Wave", "format_type" => 3}],
    "name" => "Wumpus Beyond",
    "sku_id" => "847199849233514547",
    "cover_sticker_id" => "749053689419006003",
    "description" => "Say hello to Wumpus!",
    "banner_asset_id" => "761773777976819732"
  }

  test "sticker packs" do
    respond(%{"sticker_packs" => [@pack]})

    assert {:ok, [%StickerPack{name: "Wumpus Beyond", stickers: [sticker]} = pack]} =
             Sticker.list_packs()

    assert %Lingo.Type.Sticker{name: "Wave", format_type: :lottie} = sticker
    assert pack.cover_sticker_id == "749053689419006003"
    assert pack.banner_asset_id == "761773777976819732"
    assert_received {:request, :get, "/api/v10/sticker-packs", [], nil}

    respond(@pack)
    assert {:ok, %StickerPack{id: "847199849233514549"}} = Sticker.get_pack("847199849233514549")
    assert_received {:request, :get, "/api/v10/sticker-packs/847199849233514549", [], nil}
  end
end
