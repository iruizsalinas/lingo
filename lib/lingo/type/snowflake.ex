defmodule Lingo.Type.Snowflake do
  @moduledoc false

  @type t :: String.t()

  @discord_epoch 1_420_070_400_000

  @spec timestamp(t()) :: DateTime.t()
  def timestamp(snowflake) do
    ms =
      snowflake
      |> String.to_integer()
      |> Bitwise.bsr(22)
      |> Kernel.+(@discord_epoch)

    DateTime.from_unix!(ms, :millisecond)
  end

  @spec from_timestamp(DateTime.t()) :: t()
  def from_timestamp(%DateTime{} = dt) do
    ms = DateTime.to_unix(dt, :millisecond)
    Integer.to_string(Bitwise.bsl(ms - @discord_epoch, 22))
  end

  @spec from_unix_ms(integer()) :: t()
  def from_unix_ms(ms) when is_integer(ms) do
    Integer.to_string(Bitwise.bsl(ms - @discord_epoch, 22))
  end

  @spec to_integer(t()) :: non_neg_integer()
  def to_integer(snowflake) when is_binary(snowflake), do: String.to_integer(snowflake)
  def to_integer(snowflake) when is_integer(snowflake), do: snowflake
end
