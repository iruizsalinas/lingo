# CDN

Functions for building Discord CDN URLs. All are on the `Lingo` module (delegated to `Lingo.CDN`).

## User Avatars

### `user_avatar(user)`

Returns the avatar URL for a user. Falls back to `default_avatar/1` if the user has no custom avatar. Animated avatars (hash starts with `a_`) use `.gif`, others use `.webp`.

```elixir
url = Lingo.user_avatar(user)
```

### `default_avatar(user_id)`

Returns the default avatar URL based on the user ID.

```elixir
url = Lingo.default_avatar("123456789")
# "https://cdn.discordapp.com/embed/avatars/3.png"
```

## Guild Images

### `guild_icon(guild)`

Returns the guild icon URL, or `nil` if the guild has no icon.

### `guild_splash(guild)`

Returns the guild splash URL, or `nil`.

### `guild_banner(guild)`

Returns the guild banner URL, or `nil`.

All guild image functions accept a struct with `id` and the relevant hash field (`icon`, `splash`, `banner`).

## Emojis

### `emoji_url(emoji_id, animated? \\ false)`

Returns a custom emoji URL.

```elixir
Lingo.emoji_url("123456789")         # PNG
Lingo.emoji_url("123456789", true)   # GIF
```

## Stickers

### `sticker_url(sticker_id, format_type)`

Returns a sticker URL.

| Format | URL |
|--------|-----|
| `:gif` | `https://media.discordapp.net/stickers/{id}.gif` |
| `:lottie` | `https://cdn.discordapp.com/stickers/{id}.json` |
| `:apng` | `https://cdn.discordapp.com/stickers/{id}.png` |
| other | `https://cdn.discordapp.com/stickers/{id}.png` |

## Additional CDN Functions

These are on `Lingo.CDN` directly (not re-exported on `Lingo`):

| Function | Description |
|----------|-------------|
| `Lingo.CDN.guild_discovery_splash(guild)` | Discovery splash URL |
| `Lingo.CDN.member_avatar(member)` | Guild-specific member avatar |
| `Lingo.CDN.user_banner(user)` | User banner URL |
| `Lingo.CDN.role_icon(role_id, hash)` | Role icon URL |
| `Lingo.CDN.application_icon(app_id, hash)` | Application icon URL |
| `Lingo.CDN.scheduled_event_cover(event_id, hash)` | Event cover image URL |

All return `nil` when the relevant hash field is `nil`. Animated hashes (starting with `a_`) produce `.gif` URLs, others produce `.webp`.
