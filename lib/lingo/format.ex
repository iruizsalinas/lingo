defmodule Lingo.Format do
  @moduledoc "Markdown for mentions, emojis and timestamps (rendered in each reader's locale), escaping, and message links."

  @styles %{
    short_time: "t",
    long_time: "T",
    short_date: "d",
    long_date: "D",
    short_datetime: "f",
    long_datetime: "F",
    relative: "R"
  }

  @doc """
  A timestamp, from a `DateTime` or Unix seconds. `style` is one of
  `:short_time`, `:long_time`, `:short_date`, `:long_date`,
  `:short_datetime` (the default), `:long_datetime` or `:relative`.

      Lingo.Format.timestamp(DateTime.utc_now(), :relative)
      #=> "<t:1767225600:R>"
  """
  def timestamp(datetime, style \\ :short_datetime) do
    unix =
      case datetime do
        %DateTime{} -> DateTime.to_unix(datetime)
        n when is_integer(n) -> n
      end

    case Map.get(@styles, style, style) do
      nil -> "<t:#{unix}>"
      code -> "<t:#{unix}:#{code}>"
    end
  end

  @doc "Mentions a user."
  def mention_user(id), do: "<@#{id}>"
  @doc "Links a channel."
  def mention_channel(id), do: "<##{id}>"
  @doc "Mentions a role."
  def mention_role(id), do: "<@&#{id}>"

  @doc """
  A clickable slash command. `name` may include a subcommand group and
  subcommand: `"role add"`.
  """
  def mention_command(name, command_id), do: "</#{name}:#{command_id}>"

  @doc "An emoji as message text: a `Lingo.Type.Emoji`, or any map with its `:name` and `:id`."
  def emoji(%{id: nil, name: name}), do: name

  def emoji(%{id: id, name: name} = emoji),
    do: "<#{if Map.get(emoji, :animated), do: "a"}:#{name}:#{id}>"

  @doc """
  Escapes Markdown in `text`, so it shows as typed: emphasis, code, spoilers,
  and quotes, headings and lists at the start of a line.
  """
  def escape_markdown(text) do
    text = Regex.replace(~r/[\\*_~`|]/, text, &("\\" <> &1))
    Regex.replace(~r/^(\s*)([>#-])/m, text, fn _, space, char -> space <> "\\" <> char end)
  end

  @doc "A link to a message. Pass `nil` as the guild id for DMs."
  def message_url(guild_id, channel_id, message_id) do
    "https://discord.com/channels/#{guild_id || "@me"}/#{channel_id}/#{message_id}"
  end
end
