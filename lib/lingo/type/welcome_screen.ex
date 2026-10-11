defmodule Lingo.Type.WelcomeScreen do
  @moduledoc """
  The screen a community guild shows new members: its `description` and up
  to 5 `welcome_channels`, maps with atom keys.
  """

  @type welcome_channel :: %{
          channel_id: String.t(),
          description: String.t(),
          emoji_id: String.t() | nil,
          emoji_name: String.t() | nil
        }
  @type t :: %__MODULE__{description: String.t() | nil, welcome_channels: [welcome_channel()]}

  defstruct [:description, welcome_channels: []]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      description: data["description"],
      welcome_channels: Lingo.Type.Parse.list(data["welcome_channels"], &welcome_channel/1)
    }
  end

  defp welcome_channel(data) do
    %{
      channel_id: data["channel_id"],
      description: data["description"],
      emoji_id: data["emoji_id"],
      emoji_name: data["emoji_name"]
    }
  end
end
