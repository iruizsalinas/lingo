defmodule Lingo.Type.SnowflakeTest do
  use ExUnit.Case, async: true

  alias Lingo.Type.Snowflake

  describe "timestamp/1" do
    test "extracts creation time from a known snowflake" do
      # snowflake 0 -> epoch (2015-01-01)
      dt = Snowflake.timestamp("0")
      assert dt.year == 2015
      assert dt.month == 1
      assert dt.day == 1
    end

    test "extracts correct year from a real snowflake" do
      # 1200000000000000000 >> 22 + epoch = Jan 2024
      dt = Snowflake.timestamp("1200000000000000000")
      assert dt.year == 2024
      assert dt.month == 1
    end
  end

  describe "to_integer/1" do
    test "converts string to integer" do
      assert Snowflake.to_integer("123456") == 123_456
    end

    test "passes through integer" do
      assert Snowflake.to_integer(789) == 789
    end
  end
end
