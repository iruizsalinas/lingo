defmodule Lingo.CheckError do
  @moduledoc """
  A command that didn't pass one of its `:checks`, or is on cooldown (see
  `Lingo.Bot.Commands.command/3`).

  Without a `c:Lingo.Bot.handle_error/2`, Lingo answers the user with
  `message` in an ephemeral reply. With one, the callback gets this error and
  the context, and answers as it likes.

  `reason` is one of `:guild_only`, `:dm_only`, `:nsfw`, `:owner_only`,
  `{:missing_permissions, permissions}`, `{:bot_missing_permissions,
  permissions}`, `{:cooldown, retry_after_ms}` or `{:check, function}` for a
  custom check that failed.
  """

  defexception [:reason, :message]

  @type t :: %__MODULE__{reason: term(), message: String.t()}

  @doc false
  def new(reason, message \\ nil),
    do: %__MODULE__{reason: reason, message: message || default_message(reason)}

  defp default_message(:guild_only), do: "This command only works in a server."
  defp default_message(:dm_only), do: "This command only works in DMs."
  defp default_message(:nsfw), do: "This command only works in age-restricted channels."
  defp default_message(:owner_only), do: "Only the bot's owners can use this command."

  defp default_message({:missing_permissions, perms}),
    do: "You need these permissions: #{names(perms)}."

  defp default_message({:bot_missing_permissions, perms}),
    do: "I need these permissions: #{names(perms)}."

  defp default_message({:cooldown, ms}),
    do: "This command is on cooldown, try again in #{max(div(ms + 999, 1000), 1)}s."

  defp default_message(_reason), do: "You can't use this command here."

  defp names(perms),
    do: Enum.map_join(perms, ", ", &(&1 |> to_string() |> String.replace("_", " ")))
end
