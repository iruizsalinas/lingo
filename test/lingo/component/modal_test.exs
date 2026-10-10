defmodule Lingo.Component.ModalTest do
  use ExUnit.Case, async: true

  test "label builder" do
    l =
      Lingo.Component.Modal.label(
        "Your name",
        Lingo.Component.Modal.text_input("name", "Name"),
        description: "Enter your full name"
      )

    assert l.type == 18
    assert l.label == "Your name"
    assert l.component.type == 4
    assert l.description == "Enter your full name"
  end

  test "file_upload builder" do
    fu =
      Lingo.Component.Modal.file_upload("upload", max_values: 5, file_types: ["image", ".pdf"])

    assert fu.type == 19
    assert fu.custom_id == "upload"
    assert fu.max_values == 5
    assert fu.file_types == ["image", ".pdf"]
  end

  test "radio_group builder" do
    rg =
      Lingo.Component.Modal.radio_group("color", [
        Lingo.Component.select_option("Red", "red"),
        Lingo.Component.select_option("Blue", "blue")
      ])

    assert rg.type == 21
    assert length(rg.options) == 2
  end

  test "checkbox_group builder" do
    cg =
      Lingo.Component.Modal.checkbox_group(
        "toppings",
        [
          Lingo.Component.select_option("Cheese", "cheese"),
          Lingo.Component.select_option("Peppers", "peppers", default: true)
        ],
        min_values: 1
      )

    assert cg.type == 22
    assert cg.min_values == 1
    assert Enum.at(cg.options, 1).default == true
  end

  test "checkbox builder" do
    cb = Lingo.Component.Modal.checkbox("agree", default: true)
    assert cb.type == 23
    assert cb.custom_id == "agree"
    assert cb.default == true
  end

  test "checkbox with default false is preserved" do
    cb = Lingo.Component.Modal.checkbox("tos", default: false)
    assert cb.default == false
  end

  test "modal builder" do
    m =
      Lingo.Component.Modal.modal("my_modal", "Feedback", [
        Lingo.Component.Modal.label(
          "Comment",
          Lingo.Component.Modal.text_input("comment", "Comment")
        )
      ])

    assert m.custom_id == "my_modal"
    assert m.title == "Feedback"
    assert length(m.components) == 1
  end

  test "text_input sends required: false since Discord defaults it to true" do
    assert Lingo.Component.Modal.text_input("notes", style: :paragraph, required: false) == %{
             type: 4,
             custom_id: "notes",
             style: 2,
             required: false
           }

    refute Map.has_key?(Lingo.Component.Modal.text_input("notes", []), :required)
    assert Lingo.Component.Modal.text_input("notes", style: 2).style == 2
  end

  test "modal-capable selects and checkbox groups accept required" do
    assert Lingo.Component.string_select("s", options: [], required: false).required == false
    assert Lingo.Component.user_select("u", required: false).required == false
    assert Lingo.Component.role_select("r", required: false).required == false
    assert Lingo.Component.mentionable_select("m", required: false).required == false
    assert Lingo.Component.channel_select("c", required: false).required == false
    assert Lingo.Component.Modal.checkbox_group("g", [], required: false).required == false
    refute Map.has_key?(Lingo.Component.user_select("u"), :required)
  end
end
