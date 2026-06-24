defmodule LingoTest do
  use ExUnit.Case, async: true

  describe "public API" do
    test "interaction responses accept options" do
      assert {:module, Lingo} = Code.ensure_loaded(Lingo)
      assert function_exported?(Lingo, :create_interaction_response, 5)
    end
  end
end
