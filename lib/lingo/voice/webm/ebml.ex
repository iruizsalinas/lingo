defmodule Lingo.Voice.WebM.EBML do
  @moduledoc false

  # EBML element headers: variable-length IDs and sizes (RFC 8794, section 4).

  import Bitwise

  def element_header(buffer) do
    with {:ok, id, rest} <- decode_id(buffer),
         {:ok, size, length, rest} <- decode_vint_with_length(rest) do
      {:ok, id, if(size == (1 <<< (7 * length)) - 1, do: :unknown, else: size), rest}
    end
  end

  # element IDs keep their length marker
  def decode_id(<<first, _::binary>> = buffer) do
    length = vint_length(first)

    case buffer do
      <<id::unit(8)-size(^length), rest::binary>> -> {:ok, id, rest}
      _incomplete -> :more
    end
  end

  def decode_id(<<>>), do: :more

  def decode_vint(buffer) do
    with {:ok, value, _length, rest} <- decode_vint_with_length(buffer), do: {:ok, value, rest}
  end

  def decode_vint_with_length(<<first, _::binary>> = buffer) do
    length = vint_length(first)
    bits = 7 * length

    case buffer do
      <<_marker::size(^length), value::size(^bits), rest::binary>> -> {:ok, value, length, rest}
      _incomplete -> :more
    end
  end

  def decode_vint_with_length(<<>>), do: :more

  # the number of leading zero bits, plus one
  def vint_length(first) do
    Enum.find(1..8, &(first >>> (8 - &1) == 1)) ||
      raise ArgumentError, "malformed WebM: invalid variable-length integer"
  end
end
