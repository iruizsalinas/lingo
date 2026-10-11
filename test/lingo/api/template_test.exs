defmodule Lingo.Api.TemplateTest do
  use ExUnit.Case, async: true

  import Lingo.FakeRest, only: [respond: 1]

  alias Lingo.Type.GuildTemplate

  setup do
    Lingo.FakeRest.start()
    :ok
  end

  test "deleting a template returns it" do
    respond(%{"code" => "hgM48av5Q69A", "name" => "Friends & Family", "usage_count" => 49})

    assert {:ok, %GuildTemplate{code: "hgM48av5Q69A", usage_count: 49}} =
             Lingo.Api.Template.delete("g1", "hgM48av5Q69A")

    assert_received {:request, :delete, "/api/v10/guilds/g1/templates/hgM48av5Q69A", [], nil}
  end
end
