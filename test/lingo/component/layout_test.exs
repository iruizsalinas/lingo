defmodule Lingo.Component.LayoutTest do
  use ExUnit.Case, async: true

  test "text_display builder" do
    td = Lingo.Component.Layout.text_display("**bold** text")
    assert td.type == 10
    assert td.content == "**bold** text"
  end

  test "section builder" do
    sec =
      Lingo.Component.Layout.section(
        [Lingo.Component.Layout.text_display("hello")],
        Lingo.Component.Layout.thumbnail("https://example.com/img.png")
      )

    assert sec.type == 9
    assert length(sec.components) == 1
    assert sec.accessory.type == 11
  end

  test "thumbnail builder" do
    th =
      Lingo.Component.Layout.thumbnail("https://example.com/img.png", description: "alt text")

    assert th.type == 11
    assert th.media == %{url: "https://example.com/img.png"}
    assert th.description == "alt text"
  end

  test "media_gallery builder" do
    gallery =
      Lingo.Component.Layout.media_gallery([
        Lingo.Component.Layout.gallery_item("https://example.com/a.png"),
        Lingo.Component.Layout.gallery_item("https://example.com/b.png",
          description: "B",
          spoiler: true
        )
      ])

    assert gallery.type == 12
    assert length(gallery.items) == 2
    assert Enum.at(gallery.items, 1).spoiler == true
  end

  test "file builder" do
    f = Lingo.Component.Layout.file("attachment://image.png", spoiler: true)
    assert f.type == 13
    assert f.file == %{url: "attachment://image.png"}
    assert f.spoiler == true
  end

  test "separator builder defaults" do
    sep = Lingo.Component.Layout.separator()
    assert sep.type == 14
    refute Map.has_key?(sep, :divider)
    refute Map.has_key?(sep, :spacing)
  end

  test "separator with divider false and large spacing" do
    sep = Lingo.Component.Layout.separator(divider: false, spacing: :large)
    assert sep.type == 14
    assert sep.divider == false
    assert sep.spacing == 2
  end

  test "container builder" do
    c =
      Lingo.Component.Layout.container(
        [Lingo.Component.Layout.text_display("inside")],
        accent_color: 0xFF0000,
        spoiler: true
      )

    assert c.type == 17
    assert length(c.components) == 1
    assert c.accent_color == 0xFF0000
    assert c.spoiler == true
  end

  test "gallery_item helper" do
    gi =
      Lingo.Component.Layout.gallery_item("https://example.com/pic.png", description: "A pic")

    assert gi.media == %{url: "https://example.com/pic.png"}
    assert gi.description == "A pic"
  end

  test "unfurled_media helper" do
    um = Lingo.Component.Layout.unfurled_media("https://example.com/img.png")
    assert um == %{url: "https://example.com/img.png"}
  end

  test "V2 composition encodes to JSON" do
    payload =
      Lingo.Component.Layout.container(
        [
          Lingo.Component.Layout.text_display("Welcome!"),
          Lingo.Component.Layout.separator(spacing: :large),
          Lingo.Component.Layout.section(
            [Lingo.Component.Layout.text_display("Click the button")],
            Lingo.Component.button(custom_id: "go", label: "Go", style: :primary)
          ),
          Lingo.Component.Layout.media_gallery([
            Lingo.Component.Layout.gallery_item("https://example.com/a.png")
          ]),
          Lingo.Component.action_row([
            Lingo.Component.button(custom_id: "ok", label: "OK", style: :success)
          ])
        ],
        accent_color: 0x5865F2
      )

    json = JSON.encode!(payload)
    assert is_binary(json)
  end
end
