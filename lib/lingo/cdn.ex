defmodule Lingo.CDN do
  @moduledoc """
  URLs for images on Discord's CDN.

  Images come as WebP, animated ones too (`?animated=true`), as Discord
  recommends: images uploaded as WebP or AVIF don't convert cleanly to GIF.
  Functions taking `opts` accept `:size` (a power of 2 from 16 to 4096) and
  `:format` (`:webp`, `:png`, `:jpg`, `:gif` or `:avif`).

      Lingo.CDN.user_avatar(user, size: 128)
      Lingo.CDN.guild_icon(guild, format: :png)
  """

  import Bitwise

  @base "https://cdn.discordapp.com"

  @doc "A user's avatar URL, or their default avatar's."
  def user_avatar(user, opts \\ [])

  def user_avatar(%{id: id, avatar: nil} = user, _opts),
    do: default_avatar(id, Map.get(user, :discriminator))

  def user_avatar(%{id: id, avatar: hash}, opts), do: image("avatars/#{id}", hash, opts)

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

  @doc "A user's profile banner URL, or `nil`."
  def user_banner(user, opts \\ [])
  def user_banner(%{banner: nil}, _opts), do: nil
  def user_banner(%{id: id, banner: hash}, opts), do: image("banners/#{id}", hash, opts)

  @doc "A user's or member's avatar decoration URL, or `nil`."
  def avatar_decoration(%{avatar_decoration_data: %{"asset" => asset}}),
    do: "#{@base}/avatar-decoration-presets/#{asset}.png"

  def avatar_decoration(_user_or_member), do: nil

  @doc "The badge of a user's server tag, or `nil`."
  def guild_tag_badge(user, opts \\ [])

  def guild_tag_badge(%{primary_guild: %{"identity_guild_id" => gid, "badge" => hash}}, opts)
      when is_binary(gid) and is_binary(hash),
      do: url("guild-tag-badges/#{gid}/#{hash}", "png", opts)

  def guild_tag_badge(_user, _opts), do: nil

  @doc "A member's guild-specific avatar URL, or `nil`."
  def member_avatar(member, opts \\ []), do: member_image(member, :avatar, "avatars", opts)

  @doc "A member's guild-specific banner URL, or `nil`."
  def member_banner(member, opts \\ []), do: member_image(member, :banner, "banners", opts)

  @doc "A guild's icon URL, or `nil`."
  def guild_icon(guild, opts \\ [])
  def guild_icon(%{icon: nil}, _opts), do: nil
  def guild_icon(%{id: id, icon: hash}, opts), do: image("icons/#{id}", hash, opts)

  @doc "A guild's invite splash URL, or `nil`."
  def guild_splash(guild, opts \\ [])
  def guild_splash(%{splash: nil}, _opts), do: nil
  def guild_splash(%{id: id, splash: hash}, opts), do: image("splashes/#{id}", hash, opts)

  @doc "A guild's banner URL, or `nil`."
  def guild_banner(guild, opts \\ [])
  def guild_banner(%{banner: nil}, _opts), do: nil
  def guild_banner(%{id: id, banner: hash}, opts), do: image("banners/#{id}", hash, opts)

  @doc "A guild's discovery splash URL, or `nil`."
  def guild_discovery_splash(guild, opts \\ [])
  def guild_discovery_splash(%{discovery_splash: nil}, _opts), do: nil

  def guild_discovery_splash(%{id: id, discovery_splash: hash}, opts),
    do: image("discovery-splashes/#{id}", hash, opts)

  @doc "A role's icon URL, or `nil`."
  def role_icon(role, opts \\ [])
  def role_icon(%{icon: nil}, _opts), do: nil
  def role_icon(%{id: id, icon: hash}, opts), do: image("role-icons/#{id}", hash, opts)

  @doc "A scheduled event's cover image URL, or `nil`."
  def scheduled_event_cover(event, opts \\ [])
  def scheduled_event_cover(%{image: nil}, _opts), do: nil

  def scheduled_event_cover(%{id: id, image: hash}, opts),
    do: image("guild-events/#{id}", hash, opts)

  @doc "An application icon's URL."
  def application_icon(app_id, hash, opts \\ []), do: image("app-icons/#{app_id}", hash, opts)

  @doc "A custom emoji's image URL."
  def emoji(emoji_id, animated? \\ false, opts \\ []),
    do: url("emojis/#{emoji_id}", "webp", Keyword.put_new(opts, :animated, animated?))

  @doc "A sticker's image URL, by its format type."
  def sticker(sticker_id, format_type) do
    case format_type do
      :gif -> "https://media.discordapp.net/stickers/#{sticker_id}.gif"
      :lottie -> "#{@base}/stickers/#{sticker_id}.json"
      _ -> "#{@base}/stickers/#{sticker_id}.png"
    end
  end

  @doc "A soundboard sound's audio file URL (MP3 or Ogg)."
  def soundboard_sound(sound_id), do: "#{@base}/soundboard-sounds/#{sound_id}"

  defp member_image(%{user: %{id: uid}, guild_id: gid} = member, field, dir, opts)
       when is_binary(gid) do
    case Map.get(member, field) do
      nil -> nil
      hash -> image("guilds/#{gid}/users/#{uid}/#{dir}", hash, opts)
    end
  end

  defp member_image(_member, _field, _dir, _opts), do: nil

  defp image(dir, hash, opts),
    do: url("#{dir}/#{hash}", "webp", Keyword.put_new(opts, :animated, animated?(hash)))

  defp url(path, default_format, opts) do
    format = opts |> Keyword.get(:format, default_format) |> to_string()

    query =
      [size: opts[:size], animated: if(opts[:animated] && format == "webp", do: true)]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    "#{@base}/#{path}.#{format}" <> if(query == [], do: "", else: "?" <> URI.encode_query(query))
  end

  defp animated?("a_" <> _), do: true
  defp animated?(_hash), do: false
end
