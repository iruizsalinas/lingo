defmodule Lingo.Api do
  @moduledoc """
  Discord's REST API, one module per resource: `Lingo.Api.Message`,
  `Lingo.Api.Guild`, `Lingo.Api.Member`...

  Functions are named `get`, `list`, `create`, `update` and `delete`, with a
  suffix when a resource has several kinds (`Lingo.Api.Command.update_guild/3`).
  They return `{:ok, result}`, `:ok` when Discord sends no body, or
  `{:error, %Lingo.Error{}}`, and go to the current bot (see `Lingo.with_bot/2`).

  Results are parsed: a `Lingo.Type` struct or a list of them, a map with
  atom keys for responses that hold several things (`t:Lingo.Api.Thread.archived/0`),
  or the value itself when Discord wraps just one (`Lingo.Api.Guild.get_prune_count/2`
  returns the count). Timestamps are `DateTime`s and Discord's numeric codes
  atoms, as in the structs.

  Calls always contact Discord. Successful responses for cacheable resources
  refresh enabled caches under their policies; delayed responses are skipped
  when the cache changed during the request. Complete role lists also remove
  missing cached roles. See `Lingo.Cache` for supported synchronization behavior.

  Request bodies are maps or keyword lists with Discord's field names, and
  options take `:reason` for the audit log where Discord supports one:

      Lingo.Api.Channel.update(channel_id, [name: "general"], reason: "tidy up")
  """

  @typedoc "A Discord id (a snowflake, as a string)."
  @type id :: Lingo.Snowflake.t()

  @typedoc "A request body: a map or keyword list with Discord's field names."
  @type params :: map() | keyword()

  @typedoc "A message body: a string for plain content, or message fields such as `:content`, `:embeds` and `:files`."
  @type content :: String.t() | params()

  @typedoc "The result of a call that returns something."
  @type result(value) :: {:ok, value} | {:error, Lingo.Error.t()}

  @typedoc "The result of a call Discord answers with no body."
  @type result :: :ok | {:error, Lingo.Error.t()}
end
