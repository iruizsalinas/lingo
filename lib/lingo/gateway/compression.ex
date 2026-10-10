defmodule Lingo.Gateway.Compression do
  @moduledoc false

  # Gateway transport compression: one decompression context per connection.
  #
  # zlib-stream: messages end with Z_SYNC_FLUSH, so data is buffered until
  # that suffix arrives. zstd-stream: every WebSocket message is a whole
  # payload, but the zstd frame never ends; the context is fed message by
  # message (OTP 28's :zstd).

  @zlib_suffix <<0x00, 0x00, 0xFF, 0xFF>>

  @type type :: :zlib | :zstd

  @type t :: %__MODULE__{
          type: type(),
          context: :zlib.zstream() | reference(),
          buffer: iodata()
        }

  defstruct [:context, type: :zlib, buffer: []]

  @doc "Whether this node can decompress zstd-stream (OTP 28 or later)."
  @spec zstd_available?() :: boolean()
  def zstd_available?, do: Code.ensure_loaded?(:zstd)

  @spec new(type()) :: t()
  def new(type \\ :zlib)

  def new(:zlib) do
    z = :zlib.open()
    :zlib.inflateInit(z)
    %__MODULE__{type: :zlib, context: z}
  end

  def new(:zstd) do
    {:ok, context} = apply(:zstd, :context, [:decompress])
    %__MODULE__{type: :zstd, context: context}
  end

  @doc "Feeds one WebSocket message; returns the payload once one is complete."
  @spec push(t(), iodata()) :: {t(), binary() | nil}
  def push(%__MODULE__{type: :zstd} = state, data),
    do: {state, zstd_stream(state.context, data, [])}

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

  def push(%__MODULE__{} = state, data), do: push(state, IO.iodata_to_binary(data))

  # :zstd.stream/2 hands back what it couldn't take yet as a remainder
  defp zstd_stream(context, data, acc) do
    case apply(:zstd, :stream, [context, data]) do
      {:continue, remainder, output} -> zstd_stream(context, remainder, [acc, output])
      {_continue_or_done, output} -> finish([acc, output])
    end
  end

  defp finish(output) do
    case IO.iodata_to_binary(output) do
      "" -> nil
      payload -> payload
    end
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{type: :zstd, context: context}) do
    apply(:zstd, :close, [context])
    :ok
  catch
    :error, _ -> :ok
  end

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
