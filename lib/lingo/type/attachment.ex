defmodule Lingo.Type.Attachment do
  @moduledoc "A file attached to a message."

  @type t :: %__MODULE__{
          id: String.t(),
          filename: String.t(),
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
          flags: integer()
        }

  defstruct [
    :id,
    :filename,
    :description,
    :content_type,
    :size,
    :url,
    :proxy_url,
    :height,
    :width,
    :duration_secs,
    :waveform,
    ephemeral: false,
    flags: 0
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      filename: data["filename"],
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
      flags: data["flags"] || 0
    }
  end
end
