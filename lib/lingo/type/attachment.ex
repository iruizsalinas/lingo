defmodule Lingo.Type.Attachment do
  @moduledoc "A file attached to a message."

  alias Lingo.Type.User

  @type t :: %__MODULE__{
          id: String.t(),
          filename: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          content_type: String.t() | nil,
          size: integer(),
          url: String.t(),
          proxy_url: String.t(),
          height: integer() | nil,
          width: integer() | nil,
          ephemeral: boolean(),
          duration_secs: float() | nil,
          waveform: String.t() | nil,
          placeholder: String.t() | nil,
          placeholder_version: integer() | nil,
          clip_participants: [User.t()],
          clip_created_at: DateTime.t() | nil,
          application: map() | nil,
          flags: integer()
        }

  defstruct [
    :id,
    :filename,
    :title,
    :description,
    :content_type,
    :size,
    :url,
    :proxy_url,
    :height,
    :width,
    :duration_secs,
    :waveform,
    :placeholder,
    :placeholder_version,
    :clip_created_at,
    :application,
    ephemeral: false,
    clip_participants: [],
    flags: 0
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      filename: data["filename"],
      title: data["title"],
      description: data["description"],
      content_type: data["content_type"],
      size: data["size"],
      url: data["url"],
      proxy_url: data["proxy_url"],
      height: data["height"],
      width: data["width"],
      ephemeral: data["ephemeral"] || false,
      duration_secs: data["duration_secs"],
      waveform: data["waveform"],
      placeholder: data["placeholder"],
      placeholder_version: data["placeholder_version"],
      clip_participants: Enum.map(data["clip_participants"] || [], &User.new/1),
      clip_created_at: Lingo.Type.Parse.timestamp(data["clip_created_at"]),
      application: data["application"],
      flags: data["flags"] || 0
    }
  end

  @doc "Whether the attachment is marked as a spoiler."
  @spec spoiler?(t()) :: boolean()
  def spoiler?(%__MODULE__{flags: flags}), do: Lingo.Flags.has?(:attachment, flags, :is_spoiler)
end
