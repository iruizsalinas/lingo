defmodule Lingo.Voice.WebM do
  @moduledoc """
  Reads Opus packets out of WebM and Matroska audio, the container YouTube and
  most streaming sites serve Opus in.

  Parsing works on a stream of binary chunks. Container elements are entered
  rather than read whole, so live streams with clusters of unknown size work,
  and only the first Opus track's blocks are kept: everything else is skipped
  without being buffered.
  """

  alias Lingo.Voice.WebM.{Block, EBML}

  alias Lingo.Voice.Opus

  # EBML header, Segment, Tracks, TrackEntry, Cluster, BlockGroup
  @containers [0x1A45DFA3, 0x18538067, 0x1654AE6B, 0xAE, 0x1F43B675, 0xA0]
  @ebml 0x1A45DFA3
  @track_entry 0xAE
  @cluster 0x1F43B675
  @simple_block 0xA3
  @block 0xA1
  # TrackNumber, CodecID, CodecPrivate
  @track_fields %{0xD7 => :number, 0x86 => :codec, 0x63A2 => :head}

  # the largest element read whole: a block of laced Opus frames is far smaller
  @max_element 1_048_576

  @doc "Streams the Opus packets of a WebM or Matroska file."
  @spec stream!(Path.t()) :: Enumerable.t()
  def stream!(path), do: path |> File.stream!(65_536) |> packets()

  @doc "Turns a stream of WebM data chunks into a stream of Opus packets."
  @spec packets(Enumerable.t()) :: Enumerable.t()
  def packets(chunks) do
    Stream.transform(chunks, %{buffer: <<>>, skip: 0, tracks: [], opus: nil}, &parse/2)
  end

  defp parse(chunk, state), do: read(%{state | buffer: state.buffer <> chunk}, [])

  defp read(%{skip: skip, buffer: buffer} = state, packets) when skip > 0 do
    case buffer do
      <<_skipped::binary-size(^skip), rest::binary>> ->
        read(%{state | skip: 0, buffer: rest}, packets)

      _short ->
        {Enum.reverse(packets), %{state | skip: skip - byte_size(buffer), buffer: <<>>}}
    end
  end

  defp read(state, packets) do
    with {:ok, id, size, body} <- EBML.element_header(state.buffer),
         {:ok, state, packets} <- element(id, size, %{state | buffer: body}, packets) do
      read(state, packets)
    else
      :more -> {Enum.reverse(packets), state}
    end
  end

  defp element(id, _size, state, packets) when id in @containers,
    do: {:ok, enter(id, state), packets}

  defp element(_id, :unknown, _state, _packets),
    do: raise(ArgumentError, "malformed WebM: an element of unknown size")

  # a block of another track is skipped as soon as its track number is read
  defp element(id, size, state, packets) when id in [@simple_block, @block] do
    case EBML.decode_vint(state.buffer) do
      {:ok, track, _rest} when track != state.opus -> {:ok, %{state | skip: size}, packets}
      :more when byte_size(state.buffer) < size -> :more
      _ours -> with_body(size, state, &{:ok, &2, Enum.reverse(Block.frames(&1), packets)})
    end
  end

  defp element(id, size, state, packets) when is_map_key(@track_fields, id),
    do: with_body(size, state, &{:ok, put_track_field(&2, @track_fields[id], &1), packets})

  defp element(_id, size, state, packets), do: {:ok, %{state | skip: size}, packets}

  defp with_body(size, _state, _fun) when size > @max_element,
    do: raise(ArgumentError, "malformed WebM: a #{size}-byte element where audio was expected")

  defp with_body(size, state, fun) do
    case state.buffer do
      <<body::binary-size(^size), rest::binary>> -> fun.(body, %{state | buffer: rest})
      _incomplete -> :more
    end
  end

  # a new EBML header starts a new file, as when a live stream restarts
  defp enter(@ebml, state), do: %{state | tracks: [], opus: nil}
  defp enter(@track_entry, state), do: %{state | tracks: [%{} | state.tracks]}

  defp enter(@cluster, %{opus: nil} = state) do
    codecs = state.tracks |> Enum.map(& &1[:codec]) |> Enum.reject(&is_nil/1) |> Enum.join(", ")
    raise ArgumentError, "no Opus track in this WebM (found: #{codecs}); play it through ffmpeg"
  end

  defp enter(_container, state), do: state

  defp put_track_field(%{tracks: []}, _field, _data),
    do: raise(ArgumentError, "malformed WebM: track data outside a track")

  defp put_track_field(%{tracks: [track | tracks]} = state, field, data) do
    value = if field == :number, do: :binary.decode_unsigned(data), else: data
    track = Map.put(track, field, value)
    if match?(%{codec: "A_OPUS", head: _}, track), do: check_head!(track.head)

    # the first Opus track is the one we play
    opus =
      case track do
        %{codec: "A_OPUS", number: number} when state.opus == nil -> number
        _other -> state.opus
      end

    %{state | tracks: [track | tracks], opus: opus}
  end

  defp check_head!(head) do
    case Opus.check_head(head) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  ## Blocks (RFC 9559, section 10)

  ## EBML variable-length integers (RFC 8794, section 4)
end
