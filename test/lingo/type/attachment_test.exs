defmodule Lingo.Type.AttachmentTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.Attachment

  test "parses titles, placeholders and clips" do
    attachment =
      Attachment.new(%{
        "id" => "1",
        "title" => "My clip",
        "placeholder" => "3PcNNYSFeXh/d3eld0iHZoZgVwh2",
        "placeholder_version" => 1,
        "clip_participants" => [%{"id" => "42", "username" => "u"}],
        "clip_created_at" => "2026-10-01T12:00:00+00:00",
        "application" => %{"id" => "9"},
        "flags" => 1
      })

    assert attachment.title == "My clip"
    assert attachment.placeholder_version == 1
    assert [%Lingo.Type.User{id: "42"}] = attachment.clip_participants
    assert %DateTime{year: 2026} = attachment.clip_created_at
    assert %Lingo.Type.Application{id: "9"} = attachment.application
    assert Lingo.Flags.has?(:attachment, attachment.flags, :is_clip)
    refute Attachment.spoiler?(attachment)
  end

  test "fields Discord leaves out have defaults" do
    assert %Attachment{clip_participants: [], title: nil} = Attachment.new(%{"id" => "1"})
  end
end
