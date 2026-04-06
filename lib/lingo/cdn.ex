defmodule Lingo.CDN do
  @moduledoc false

  import Bitwise

  @base "https://cdn.discordapp.com"

  def user_avatar(%{id: id, avatar: nil}), do: default_avatar(id)
  def user_avatar(%{id: id, avatar: hash}), do: "#{@base}/avatars/#{id}/#{hash}.#{ext(hash)}"

  def default_avatar(user_id) do
    index = rem(String.to_integer(user_id) >>> 22, 6)
    "#{@base}/embed/avatars/#{index}.png"
  end

  def guild_icon(%{icon: nil}), do: nil
  def guild_icon(%{id: id, icon: hash}), do: "#{@base}/icons/#{id}/#{hash}.#{ext(hash)}"

  def guild_splash(%{splash: nil}), do: nil
  def guild_splash(%{id: id, splash: hash}), do: "#{@base}/splashes/#{id}/#{hash}.#{ext(hash)}"

  def guild_banner(%{banner: nil}), do: nil
  def guild_banner(%{id: id, banner: hash}), do: "#{@base}/banners/#{id}/#{hash}.#{ext(hash)}"

  def guild_discovery_splash(%{discovery_splash: nil}), do: nil

  def guild_discovery_splash(%{id: id, discovery_splash: hash}) do
    "#{@base}/discovery-splashes/#{id}/#{hash}.#{ext(hash)}"
  end

  def member_avatar(%{avatar: nil}), do: nil
  def member_avatar(%{user: nil}), do: nil

  def member_avatar(%{guild_id: gid, user: %{id: uid}, avatar: hash}) do
    "#{@base}/guilds/#{gid}/users/#{uid}/avatars/#{hash}.#{ext(hash)}"
  end

  def emoji_url(emoji_id, animated? \\ false) do
    ext = if animated?, do: "gif", else: "png"
    "#{@base}/emojis/#{emoji_id}.#{ext}"
  end

  def user_banner(%{banner: nil}), do: nil
  def user_banner(%{id: id, banner: hash}), do: "#{@base}/banners/#{id}/#{hash}.#{ext(hash)}"

  def role_icon(role_id, hash), do: "#{@base}/role-icons/#{role_id}/#{hash}.#{ext(hash)}"

  def application_icon(app_id, hash), do: "#{@base}/app-icons/#{app_id}/#{hash}.#{ext(hash)}"

  def scheduled_event_cover(event_id, hash),
    do: "#{@base}/guild-events/#{event_id}/#{hash}.#{ext(hash)}"

  def sticker_url(sticker_id, format_type) do
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
