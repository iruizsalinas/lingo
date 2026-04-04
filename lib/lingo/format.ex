defmodule Lingo.Format do
  @moduledoc false

  @styles %{
    short_time: "t",
    long_time: "T",
    short_date: "d",
    long_date: "D",
    short_datetime: "f",
    long_datetime: "F",
    relative: "R"
  }

  def timestamp(datetime, style \\ :short_datetime) do
    unix =
      case datetime do
        %DateTime{} -> DateTime.to_unix(datetime)
        n when is_integer(n) -> n
      end

    case Map.get(@styles, style) do
      nil -> "<t:#{unix}>"
      code -> "<t:#{unix}:#{code}>"
    end
  end

  def mention_user(id), do: "<@#{id}>"
  def mention_channel(id), do: "<##{id}>"
  def mention_role(id), do: "<@&#{id}>"
end
