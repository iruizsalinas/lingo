defmodule Lingo.Event.ChannelInfo do
  @moduledoc """
  The payload of `:channel_info`, the answer to
  `Lingo.Gateway.request_channel_info/2`: the requested fields of a guild's
  channels, such as voice channel statuses.
  """

  @type channel :: %{
          id: String.t(),
          status: String.t() | nil,
          voice_start_time: DateTime.t() | nil
        }
  @type t :: %__MODULE__{guild_id: String.t(), channels: [channel()]}

  defstruct [:guild_id, channels: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      guild_id: data["guild_id"],
      channels: Enum.map(data["channels"] || [], &channel/1)
    }
  end

  defp channel(data) do
    %{
      id: data["id"],
      status: data["status"],
      voice_start_time: Lingo.Type.Parse.unix(data["voice_start_time"])
    }
  end
end
