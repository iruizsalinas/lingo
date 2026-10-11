defmodule Lingo.Type.VoiceState do
  @moduledoc "A user's voice connection state in a guild."

  alias Lingo.Type.{Member, Parse}

  @type t :: %__MODULE__{
          guild_id: String.t() | nil,
          channel_id: String.t() | nil,
          user_id: String.t(),
          member: Member.t() | nil,
          session_id: String.t(),
          deaf: boolean(),
          mute: boolean(),
          self_deaf: boolean(),
          self_mute: boolean(),
          self_stream: boolean(),
          self_video: boolean(),
          suppress: boolean(),
          request_to_speak_timestamp: DateTime.t() | nil
        }

  defstruct [
    :guild_id,
    :channel_id,
    :user_id,
    :member,
    :session_id,
    :request_to_speak_timestamp,
    deaf: false,
    mute: false,
    self_deaf: false,
    self_mute: false,
    self_stream: false,
    self_video: false,
    suppress: false
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      guild_id: data["guild_id"],
      channel_id: data["channel_id"],
      user_id: data["user_id"],
      member: member(data["member"], data["guild_id"]),
      session_id: data["session_id"],
      deaf: data["deaf"] || false,
      mute: data["mute"] || false,
      self_deaf: data["self_deaf"] || false,
      self_mute: data["self_mute"] || false,
      self_stream: data["self_stream"] || false,
      self_video: data["self_video"] || false,
      suppress: data["suppress"] || false,
      request_to_speak_timestamp: Parse.timestamp(data["request_to_speak_timestamp"])
    }
  end

  defp member(nil, _guild_id), do: nil
  defp member(data, guild_id), do: data |> Parse.put_guild_id(guild_id) |> Member.new()
end
