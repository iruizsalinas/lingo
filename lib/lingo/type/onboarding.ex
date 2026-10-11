defmodule Lingo.Type.Onboarding do
  @moduledoc """
  A guild's onboarding: the questions (`prompts`) new members answer and the
  channels they get by default.

  `mode` is `:default` (only default channels count towards the constraints
  Discord enforces) or `:advanced` (questions count too). Prompts and their
  options are maps with atom keys; a prompt's `type` is `:multiple_choice` or
  `:dropdown`.
  """

  alias Lingo.Type.{Emoji, Parse}

  @type option :: %{
          id: String.t(),
          channel_ids: [String.t()],
          role_ids: [String.t()],
          emoji: Emoji.t() | nil,
          emoji_id: String.t() | nil,
          emoji_name: String.t() | nil,
          emoji_animated: boolean() | nil,
          title: String.t(),
          description: String.t() | nil
        }
  @type prompt :: %{
          id: String.t(),
          type: :multiple_choice | :dropdown | integer(),
          options: [option()],
          title: String.t(),
          single_select: boolean(),
          required: boolean(),
          in_onboarding: boolean()
        }
  @type t :: %__MODULE__{
          guild_id: String.t(),
          prompts: [prompt()],
          default_channel_ids: [String.t()],
          enabled: boolean(),
          mode: :default | :advanced | integer()
        }

  defstruct [:guild_id, prompts: [], default_channel_ids: [], enabled: false, mode: :default]

  @modes %{0 => :default, 1 => :advanced}
  @prompt_types %{0 => :multiple_choice, 1 => :dropdown}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      guild_id: data["guild_id"],
      prompts: Parse.list(data["prompts"], &prompt/1),
      default_channel_ids: data["default_channel_ids"] || [],
      enabled: data["enabled"] || false,
      mode: Map.get(@modes, data["mode"], data["mode"] || :default)
    }
  end

  defp prompt(data) do
    %{
      id: data["id"],
      type: Map.get(@prompt_types, data["type"], data["type"]),
      options: Parse.list(data["options"], &option/1),
      title: data["title"],
      single_select: data["single_select"] || false,
      required: data["required"] || false,
      in_onboarding: data["in_onboarding"] || false
    }
  end

  defp option(data) do
    %{
      id: data["id"],
      channel_ids: data["channel_ids"] || [],
      role_ids: data["role_ids"] || [],
      emoji: Emoji.new(data["emoji"]),
      emoji_id: data["emoji_id"],
      emoji_name: data["emoji_name"],
      emoji_animated: data["emoji_animated"],
      title: data["title"],
      description: data["description"]
    }
  end
end
