defmodule Lingo.Gateway.ETF do
  @moduledoc false

  # Erlang External Term Format, the gateway's `encoding=etf`.
  #
  # Decoding never creates atoms (so it is safe on any input) and produces
  # what the JSON encoding would: string keys, atoms as strings (`nil`,
  # `true` and `false` aside), byte lists as lists, and integers too large for
  # 32 bits, which are snowflakes and bitfields, as strings. Activity
  # timestamps are the exception: JSON sends them as numbers too.

  @numeric_keys ~w(start end created_at since)

  @spec encode(map()) :: binary()
  def encode(payload), do: :erlang.term_to_binary(payload)

  @spec decode(binary()) :: {:ok, term()} | :error
  def decode(<<131, data::binary>>) do
    case term(data, nil) do
      {term, <<>>} -> {:ok, term}
      _trailing -> :error
    end
  rescue
    _malformed -> :error
  end

  def decode(_data), do: :error

  # compressed term
  defp term(<<80, size::32, data::binary>>, key) do
    <<inflated::binary-size(^size)>> = :zlib.uncompress(data)
    {term, <<>>} = term(inflated, key)
    {term, <<>>}
  end

  defp term(<<97, int, rest::binary>>, _key), do: {int, rest}
  defp term(<<98, int::signed-32, rest::binary>>, _key), do: {int, rest}

  defp term(<<110, n, sign, digits::binary-size(n), rest::binary>>, key),
    do: {big(sign, digits, key), rest}

  defp term(<<111, n::32, sign, digits::binary-size(n), rest::binary>>, key),
    do: {big(sign, digits, key), rest}

  defp term(<<70, float::float-64, rest::binary>>, _key), do: {float, rest}

  defp term(<<99, float::binary-31, rest::binary>>, _key),
    do: {float |> String.trim_trailing(<<0>>) |> String.to_float(), rest}

  defp term(<<tag, len::16, name::binary-size(len), rest::binary>>, _key) when tag in [100, 118],
    do: {atom(name), rest}

  defp term(<<tag, len, name::binary-size(len), rest::binary>>, _key) when tag in [115, 119],
    do: {atom(name), rest}

  defp term(<<109, len::32, bin::binary-size(len), rest::binary>>, _key), do: {bin, rest}

  defp term(<<107, len::16, bytes::binary-size(len), rest::binary>>, _key),
    do: {:binary.bin_to_list(bytes), rest}

  defp term(<<106, rest::binary>>, _key), do: {[], rest}

  defp term(<<108, count::32, rest::binary>>, key) do
    {items, rest} = items(rest, count, key, [])
    # proper lists end in an empty list
    {[], rest} = term(rest, key)
    {items, rest}
  end

  defp term(<<104, arity, rest::binary>>, key), do: items(rest, arity, key, [])
  defp term(<<105, arity::32, rest::binary>>, key), do: items(rest, arity, key, [])
  defp term(<<116, arity::32, rest::binary>>, _key), do: pairs(rest, arity, [])

  defp items(rest, 0, _key, acc), do: {Enum.reverse(acc), rest}

  defp items(data, count, key, acc) do
    {item, rest} = term(data, key)
    items(rest, count - 1, key, [item | acc])
  end

  defp pairs(rest, 0, acc), do: {Map.new(acc), rest}

  defp pairs(data, count, acc) do
    {key, rest} = term(data, nil)
    key = if is_binary(key), do: key, else: to_string(key)
    {value, rest} = term(rest, key)
    pairs(rest, count - 1, [{key, value} | acc])
  end

  defp atom("nil"), do: nil
  defp atom("true"), do: true
  defp atom("false"), do: false
  defp atom(name), do: name

  defp big(sign, digits, key) do
    int = :binary.decode_unsigned(digits, :little)
    int = if sign == 1, do: -int, else: int
    if key in @numeric_keys, do: int, else: Integer.to_string(int)
  end
end
