defmodule Lingo.ComponentTest do
  use ExUnit.Case, async: true

  test "action_row builder returns a ready-to-use map" do
    row =
      Lingo.Component.action_row([
        Lingo.Component.button(custom_id: "btn1", label: "Click", style: :primary)
      ])

    assert row.type == 1
    assert length(row.components) == 1
    assert hd(row.components).label == "Click"
  end

  test "button builder returns encoded map" do
    btn = Lingo.Component.button(custom_id: "x", label: "X", style: :danger)
    assert btn.type == 2
    assert btn.style == 4
    assert btn.label == "X"
    assert btn.custom_id == "x"
  end

  test "button premium style with sku_id" do
    btn = Lingo.Component.button(style: :premium, sku_id: "sku_123")
    assert btn.type == 2
    assert btn.style == 6
    assert btn.sku_id == "sku_123"
    refute Map.has_key?(btn, :custom_id)
  end

  test "v2 returns correct value" do
    assert Lingo.Component.v2_flag() == 32768
  end

  test "user_select builder" do
    sel = Lingo.Component.user_select("pick_user", placeholder: "Choose a user", max_values: 3)
    assert sel.type == 5
    assert sel.custom_id == "pick_user"
    assert sel.placeholder == "Choose a user"
    assert sel.max_values == 3
  end

  test "role_select builder" do
    sel = Lingo.Component.role_select("pick_role")
    assert sel.type == 6
    assert sel.custom_id == "pick_role"
  end

  test "mentionable_select builder" do
    sel = Lingo.Component.mentionable_select("pick_any", min_values: 1, max_values: 5)
    assert sel.type == 7
    assert sel.min_values == 1
    assert sel.max_values == 5
  end

  test "channel_select with channel_types" do
    sel = Lingo.Component.channel_select("pick_ch", channel_types: [0, 2])
    assert sel.type == 8
    assert sel.channel_types == [0, 2]
  end

  test "select with default_values" do
    sel =
      Lingo.Component.user_select("sel",
        default_values: [Lingo.Component.default_value("123", "user")]
      )

    assert [%{id: "123", type: "user"}] = sel.default_values
  end

  test "select_option helper" do
    so = Lingo.Component.select_option("Red", "red", description: "The color red")
    assert so.label == "Red"
    assert so.value == "red"
    assert so.description == "The color red"
  end

  test "default_value helper" do
    dv = Lingo.Component.default_value("123456", "user")
    assert dv == %{id: "123456", type: "user"}
  end

  test "builders produce JSON-safe maps" do
    row =
      Lingo.Component.action_row([
        Lingo.Component.button(custom_id: "a", label: "A", style: :success)
      ])

    assert is_binary(JSON.encode!(row))
  end
end
