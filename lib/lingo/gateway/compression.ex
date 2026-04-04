defmodule Lingo.Gateway.Compression do
  @moduledoc false

  @zlib_suffix <<0x00, 0x00, 0xFF, 0xFF>>

  @type t :: %__MODULE__{
          context: :zlib.zstream(),
          buffer: iodata()
        }

  defstruct [:context, buffer: []]

  @spec new() :: t()
  def new do
    z = :zlib.open()
    :zlib.inflateInit(z)
    %__MODULE__{context: z, buffer: []}
  end

  @spec push(t(), binary()) :: {t(), binary() | nil}
  def push(%__MODULE__{} = state, data) when is_binary(data) do
    buffer = [state.buffer, data]

    if byte_size(data) >= 4 and binary_part(data, byte_size(data) - 4, 4) == @zlib_suffix do
      decompressed =
        state.context
        |> :zlib.inflate(IO.iodata_to_binary(buffer))
        |> IO.iodata_to_binary()

      {%{state | buffer: []}, decompressed}
    else
      {%{state | buffer: buffer}, nil}
    end
  end

  def push(%__MODULE__{} = state, data) do
    bin = IO.iodata_to_binary(data)
    push(state, bin)
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{context: z}) do
    try do
      :zlib.inflateEnd(z)
    catch
      :error, _ -> :ok
    end

    :zlib.close(z)
    :ok
  end
end
