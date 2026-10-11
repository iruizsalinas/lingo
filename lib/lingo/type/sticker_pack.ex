defmodule Lingo.Type.StickerPack do
  @moduledoc "A pack of Discord's standard stickers."

  alias Lingo.Type.{Parse, Sticker}

  @type t :: %__MODULE__{
          id: String.t(),
          stickers: [Sticker.t()],
          name: String.t(),
          sku_id: String.t(),
          cover_sticker_id: String.t() | nil,
          description: String.t(),
          banner_asset_id: String.t() | nil
        }

  defstruct [:id, :name, :sku_id, :cover_sticker_id, :description, :banner_asset_id, stickers: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    struct(Parse.fields(__MODULE__, data), stickers: Parse.list(data["stickers"], &Sticker.new/1))
  end
end
