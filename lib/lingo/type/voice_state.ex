defmodule Lingo.Type.VoiceState do
  @moduledoc false

  alias Lingo.Type.Member

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
          request_to_speak_timestamp: String.t() | nil
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

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      guild_id: data["guild_id"],
      channel_id: data["channel_id"],
      user_id: data["user_id"],
      member: Member.new(data["member"]),
      session_id: data["session_id"],
      deaf: data["deaf"] || false,
      mute: data["mute"] || false,
      self_deaf: data["self_deaf"] || false,
      self_mute: data["self_mute"] || false,
      self_stream: data["self_stream"] || false,
      self_video: data["self_video"] || false,
      suppress: data["suppress"] || false,
      request_to_speak_timestamp: data["request_to_speak_timestamp"]
    }
  end
end
