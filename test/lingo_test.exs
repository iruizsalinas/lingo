defmodule LingoTest do
  use ExUnit.Case, async: true

  describe "public API" do
    test "interaction responses accept options" do
      assert {:module, Lingo.Api.Interaction} = Code.ensure_loaded(Lingo.Api.Interaction)
      assert function_exported?(Lingo.Api.Interaction, :create_response, 5)
    end
  end
end
