defmodule Lingo.Type.RoleConnectionMetadataTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.RoleConnectionMetadata

  test "parses a record and names its comparison" do
    record =
      RoleConnectionMetadata.new(%{
        "type" => 6,
        "key" => "joined_at",
        "name" => "Joined",
        "name_localizations" => %{"fr" => "Inscrit"},
        "description" => "Days since joining"
      })

    assert %RoleConnectionMetadata{
             type: :datetime_greater_than_or_equal,
             key: "joined_at",
             name: "Joined",
             name_localizations: %{"fr" => "Inscrit"},
             description: "Days since joining",
             description_localizations: nil
           } = record
  end

  test "every type Discord documents has a name, and unknown ones pass through" do
    names = Enum.map(1..8, &RoleConnectionMetadata.new(%{"type" => &1}).type)

    assert names == [
             :integer_less_than_or_equal,
             :integer_greater_than_or_equal,
             :integer_equal,
             :integer_not_equal,
             :datetime_less_than_or_equal,
             :datetime_greater_than_or_equal,
             :boolean_equal,
             :boolean_not_equal
           ]

    assert RoleConnectionMetadata.new(%{"type" => 42}).type == 42
  end
end
