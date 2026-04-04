defmodule Lingo.Type.User do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          username: String.t(),
          discriminator: String.t(),
          global_name: String.t() | nil,
          avatar: String.t() | nil,
          avatar_decoration_data: map() | nil,
          bot: boolean(),
          system: boolean(),
          mfa_enabled: boolean() | nil,
          banner: String.t() | nil,
          accent_color: integer() | nil,
          locale: String.t() | nil,
          flags: integer() | nil,
          premium_type: integer() | nil,
          public_flags: integer() | nil
        }

  defstruct [
    :id,
    :username,
    :discriminator,
    :global_name,
    :avatar,
    :avatar_decoration_data,
    :banner,
    :accent_color,
    :locale,
    :flags,
    :premium_type,
    :public_flags,
    :mfa_enabled,
    bot: false,
    system: false
  ]

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      username: data["username"],
      discriminator: data["discriminator"],
      global_name: data["global_name"],
      avatar: data["avatar"],
      avatar_decoration_data: data["avatar_decoration_data"],
      bot: data["bot"] || false,
      system: data["system"] || false,
      mfa_enabled: data["mfa_enabled"],
      banner: data["banner"],
      accent_color: data["accent_color"],
      locale: data["locale"],
      flags: data["flags"],
      premium_type: data["premium_type"],
      public_flags: data["public_flags"]
    }
  end
end
