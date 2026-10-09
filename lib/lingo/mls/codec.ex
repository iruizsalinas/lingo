defmodule Lingo.MLS.Codec do
  @moduledoc false

  # The TLS presentation language as profiled by RFC 9420, section 2.1.
  #
  # Integers are fixed-width and big-endian, so callers encode and match them
  # with plain binary syntax. Vectors carry a variable-length size prefix that
  # must use the shortest encoding. Decoders return `{value, rest}` and raise
  # ArgumentError on malformed input; Lingo.MLS.Message turns that into an
  # error tuple at the boundary.

  @spec varint(non_neg_integer()) :: binary()
  def varint(n) when n < 0x40, do: <<0::2, n::6>>
  def varint(n) when n < 0x4000, do: <<1::2, n::14>>
  def varint(n) when n < 0x40000000, do: <<2::2, n::30>>

  @spec vector(iodata()) :: iodata()
  def vector(data), do: [varint(IO.iodata_length(data)), data]

  @spec list([term()], (term() -> iodata())) :: iodata()
  def list(items, encode), do: vector(Enum.map(items, encode))

  @spec optional(term() | nil, (term() -> iodata())) :: iodata()
  def optional(nil, _encode), do: <<0>>
  def optional(value, encode), do: [<<1>>, encode.(value)]

  @spec decode_varint(binary()) :: {non_neg_integer(), binary()}
  def decode_varint(<<0::2, n::6, rest::binary>>), do: {n, rest}
  def decode_varint(<<1::2, n::14, rest::binary>>) when n >= 0x40, do: {n, rest}
  def decode_varint(<<2::2, n::30, rest::binary>>) when n >= 0x4000, do: {n, rest}
  def decode_varint(_binary), do: raise(ArgumentError, "invalid variable-length integer")

  @spec decode_vector(binary()) :: {binary(), binary()}
  def decode_vector(binary) do
    {length, rest} = decode_varint(binary)

    case rest do
      <<data::binary-size(^length), rest::binary>> -> {data, rest}
      _truncated -> raise ArgumentError, "truncated vector"
    end
  end

  @spec decode_list(binary(), (binary() -> {term(), binary()})) :: {[term()], binary()}
  def decode_list(binary, decode) do
    {data, rest} = decode_vector(binary)
    {decode_all(data, decode, []), rest}
  end

  defp decode_all(<<>>, _decode, acc), do: Enum.reverse(acc)

  defp decode_all(data, decode, acc) do
    {item, rest} = decode.(data)
    decode_all(rest, decode, [item | acc])
  end

  @spec decode_optional(binary(), (binary() -> {term(), binary()})) :: {term() | nil, binary()}
  def decode_optional(<<0, rest::binary>>, _decode), do: {nil, rest}
  def decode_optional(<<1, rest::binary>>, decode), do: decode.(rest)
  def decode_optional(_binary, _decode), do: raise(ArgumentError, "invalid optional")

  @doc "Decodes a whole binary, rejecting trailing bytes."
  @spec decode_exact(binary(), (binary() -> {term(), binary()})) :: term()
  def decode_exact(binary, decode) do
    case decode.(binary) do
      {value, <<>>} -> value
      {_value, _rest} -> raise ArgumentError, "trailing bytes"
    end
  end

  # helpers for lists of fixed-width integers, which appear all over MLS

  @spec uint16_list([non_neg_integer()]) :: iodata()
  def uint16_list(values), do: list(values, &<<&1::16>>)

  @spec decode_uint16_list(binary()) :: {[non_neg_integer()], binary()}
  def decode_uint16_list(binary),
    do: decode_list(binary, fn <<v::16, rest::binary>> -> {v, rest} end)

  @spec uint32_list([non_neg_integer()]) :: iodata()
  def uint32_list(values), do: list(values, &<<&1::32>>)

  @spec decode_uint32_list(binary()) :: {[non_neg_integer()], binary()}
  def decode_uint32_list(binary),
    do: decode_list(binary, fn <<v::32, rest::binary>> -> {v, rest} end)

  # Extension lists are kept as {type, data} pairs so unknown extensions survive a
  # decode and re-encode unchanged, which signatures over them depend on.

  @spec extensions([{non_neg_integer(), binary()}]) :: iodata()
  def extensions(extensions),
    do: list(extensions, fn {type, data} -> [<<type::16>>, vector(data)] end)

  @spec decode_extensions(binary()) :: {[{non_neg_integer(), binary()}], binary()}
  def decode_extensions(binary) do
    decode_list(binary, fn <<type::16, rest::binary>> ->
      {data, rest} = decode_vector(rest)
      {{type, data}, rest}
    end)
  end
end
