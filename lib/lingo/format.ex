defmodule Lingo.Format do
  @moduledoc "Markdown for mentions and timestamps that Discord renders in each reader's locale, and message links."

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

  @doc "A link to a message. Pass `nil` as the guild id for DMs."
  def message_url(guild_id, channel_id, message_id) do
    "https://discord.com/channels/#{guild_id || "@me"}/#{channel_id}/#{message_id}"
  end
end
