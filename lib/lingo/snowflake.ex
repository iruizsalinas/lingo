defmodule Lingo.Snowflake do
  @moduledoc """
  Discord ids ("snowflakes"). Lingo keeps them as strings, as Discord sends
  them; they encode their creation time.
  """

  @type t :: String.t()

  @discord_epoch 1_420_070_400_000

  @doc "When the object with this id was created."
  @spec to_datetime(t()) :: DateTime.t()
  def to_datetime(snowflake) do
    ms =
      snowflake
      |> String.to_integer()
      |> Bitwise.bsr(22)
      |> Kernel.+(@discord_epoch)

    DateTime.from_unix!(ms, :millisecond)
  end

  @doc "The smallest id created at `datetime`, for `before:`/`after:` pagination."
  @spec from_datetime(DateTime.t()) :: t()
  def from_datetime(%DateTime{} = dt) do
    ms = DateTime.to_unix(dt, :millisecond)
    Integer.to_string(Bitwise.bsl(ms - @discord_epoch, 22))
  end

  @doc "The smallest id created at a Unix time in milliseconds."
  @spec from_unix_ms(integer()) :: t()
  def from_unix_ms(ms) when is_integer(ms) do
    Integer.to_string(Bitwise.bsl(ms - @discord_epoch, 22))
  end

  @doc "The id as an integer."
  @spec to_integer(t()) :: non_neg_integer()
  def to_integer(snowflake) when is_binary(snowflake), do: String.to_integer(snowflake)
  def to_integer(snowflake) when is_integer(snowflake), do: snowflake
end
