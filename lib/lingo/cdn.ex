defmodule Lingo.CDN do
  @moduledoc "URLs for images on Discord's CDN. Animated images get `.gif` URLs, the rest `.webp` (`.png` for emojis and stickers)."

  import Bitwise

  @base "https://cdn.discordapp.com"

  @doc "A user's avatar URL, or their default avatar's."
  def user_avatar(%{id: id, avatar: nil} = user),
    do: default_avatar(id, Map.get(user, :discriminator))

  def user_avatar(%{id: id, avatar: hash}), do: "#{@base}/avatars/#{id}/#{hash}.#{ext(hash)}"

  # users on the legacy username system (including bots) use discriminator % 5
  @doc "The URL of the default avatar Discord gives a user without one."
  def default_avatar(user_id, discriminator \\ nil)

  def default_avatar(_user_id, discriminator)
      when is_binary(discriminator) and discriminator not in ["", "0"] do
    "#{@base}/embed/avatars/#{rem(String.to_integer(discriminator), 5)}.png"
  end

  def default_avatar(user_id, _discriminator) do
    index = rem(String.to_integer(user_id) >>> 22, 6)
    "#{@base}/embed/avatars/#{index}.png"
  end

  @doc "A guild's icon URL, or `nil`."
  def guild_icon(%{icon: nil}), do: nil
  def guild_icon(%{id: id, icon: hash}), do: "#{@base}/icons/#{id}/#{hash}.#{ext(hash)}"

  @doc "A guild's invite splash URL, or `nil`."
  def guild_splash(%{splash: nil}), do: nil
  def guild_splash(%{id: id, splash: hash}), do: "#{@base}/splashes/#{id}/#{hash}.#{ext(hash)}"

  @doc "A guild's banner URL, or `nil`."
  def guild_banner(%{banner: nil}), do: nil
  def guild_banner(%{id: id, banner: hash}), do: "#{@base}/banners/#{id}/#{hash}.#{ext(hash)}"

  @doc "A guild's discovery splash URL, or `nil`."
  def guild_discovery_splash(%{discovery_splash: nil}), do: nil

  def guild_discovery_splash(%{id: id, discovery_splash: hash}) do
    "#{@base}/discovery-splashes/#{id}/#{hash}.#{ext(hash)}"
  end

  @doc "A member's guild-specific avatar URL, or `nil`."
  def member_avatar(%{avatar: nil}), do: nil
  def member_avatar(%{user: nil}), do: nil

  def member_avatar(%{guild_id: gid, user: %{id: uid}, avatar: hash}) do
    "#{@base}/guilds/#{gid}/users/#{uid}/avatars/#{hash}.#{ext(hash)}"
  end

  @doc "A custom emoji's image URL."
  def emoji(emoji_id, animated? \\ false) do
    ext = if animated?, do: "gif", else: "png"
    "#{@base}/emojis/#{emoji_id}.#{ext}"
  end

  @doc "A user's profile banner URL, or `nil`."
  def user_banner(%{banner: nil}), do: nil
  def user_banner(%{id: id, banner: hash}), do: "#{@base}/banners/#{id}/#{hash}.#{ext(hash)}"

  @doc "A role's icon URL, or `nil`."
  def role_icon(%{icon: nil}), do: nil
  def role_icon(%{id: id, icon: hash}), do: "#{@base}/role-icons/#{id}/#{hash}.#{ext(hash)}"

  @doc "An application icon's URL."
  def application_icon(app_id, hash), do: "#{@base}/app-icons/#{app_id}/#{hash}.#{ext(hash)}"

  @doc "A scheduled event's cover image URL, or `nil`."
  def scheduled_event_cover(%{image: nil}), do: nil

  def scheduled_event_cover(%{id: id, image: hash}),
    do: "#{@base}/guild-events/#{id}/#{hash}.#{ext(hash)}"

  @doc "A sticker's image URL, by its format type."
  def sticker(sticker_id, format_type) do
    case format_type do
      :gif -> "https://media.discordapp.net/stickers/#{sticker_id}.gif"
      :lottie -> "#{@base}/stickers/#{sticker_id}.json"
      :apng -> "#{@base}/stickers/#{sticker_id}.png"
      _ -> "#{@base}/stickers/#{sticker_id}.png"
    end
  end

  defp ext("a_" <> _), do: "gif"
  defp ext(_), do: "webp"
end
