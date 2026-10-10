defmodule Lingo.Cache.Rest.Routes do
  @moduledoc false

  def plan(method, path, opts), do: route(method, String.split(path, "/", trim: true), opts)

  defp route(:delete, ["guilds", g], _), do: guild_delete(g)
  defp route(:delete, ["users", "@me", "guilds", g], _), do: guild_delete(g)

  defp route(m, ["guilds", g], _) when m in [:get, :patch, :post],
    do: [{:guilds, :one, %{"id" => g}}, {:roles, :guild_roles, %{"guild_id" => g}}]

  defp route(:get, ["guilds", g, "roles"], _), do: [{:roles, :roles, %{"guild_id" => g}}]

  defp route(m, ["guilds", g, "roles"], _) when m in [:post, :patch],
    do: [{:roles, :put, %{"guild_id" => g}}]

  defp route(:delete, ["guilds", g, "roles", id], _), do: [{:roles, :delete, {g, id}}]
  defp route(:get, ["guilds", _, "roles", "member-counts"], _), do: []

  defp route(m, ["guilds", g, "roles", id], _) when m in [:get, :patch],
    do: [{:roles, :one, %{"guild_id" => g, "id" => id}}]

  defp route(:delete, ["guilds", g, "members", id], _),
    do: for(r <- [:members, :presences, :voice_states], do: {r, :delete, {g, id}})

  defp route(m, ["guilds", g, "members"], _) when m in [:get, :post],
    do: member(:put, %{"guild_id" => g})

  defp route(:get, ["guilds", g, "members", "search"], _),
    do: member(:put, %{"guild_id" => g})

  defp route(m, ["guilds", g, "members", id], _) when m in [:get, :patch, :put],
    do: member(:put, %{"guild_id" => g, "user_id" => id})

  defp route(m, ["guilds", g, "members", id, "roles", _], _) when m in [:put, :delete],
    do: [{:members, :delete, {g, id}}]

  defp route(m, ["guilds", g, "channels"], _) when m in [:get, :post],
    do: [{:channels, :put, %{"guild_id" => g}}]

  defp route(:patch, ["guilds", g, "channels"], _),
    do: [{:channels, :prune, [{{:_, %{guild_id: g}}, [], [true]}]}]

  defp route(:get, ["guilds", g, "threads", "active"], _),
    do: [{:channels, :threads, %{"guild_id" => g}}]

  defp route(:delete, ["channels", c], _),
    do: [{:channels, :delete, c}, {:messages, :prune, [{{{c, :_}, :_}, [], [true]}]}]

  defp route(m, ["channels", c], _) when m in [:get, :patch],
    do: [{:channels, :one, %{"id" => c}}]

  defp route(m, ["channels", c, "permissions", _], _) when m in [:put, :delete],
    do: [{:channels, :delete, c}]

  defp route(:post, ["channels", c, "messages", "bulk-delete"], opts) do
    body = opts[:json] || %{}
    [{:messages, :bulk_delete, {c, body}}]
  end

  defp route(:delete, ["channels", c, "messages", id], _),
    do: [{:messages, :delete, {c, id}}]

  defp route(m, ["channels", c, "messages"], _) when m in [:get, :post],
    do: message(:put, %{"channel_id" => c})

  defp route(m, ["channels", c, "messages", id], _) when m in [:get, :patch] and id != "pins",
    do: message(:one, %{"channel_id" => c, "id" => id})

  defp route(:post, ["channels", c, "messages", id, "crosspost"], _),
    do: message(:one, %{"channel_id" => c, "id" => id})

  defp route(:get, ["channels", c, "messages", "pins"], _),
    do: message(:pins, %{"channel_id" => c})

  defp route(:post, ["channels", _, "messages", _, "threads"], _),
    do: [{:channels, :one, %{}}]

  defp route(:post, ["channels", _, "threads"], _), do: [{:channels, :one, %{}}]

  defp route(:get, ["channels", _, "threads", "archived", _], _),
    do: [{:channels, :threads, %{}}]

  defp route(:get, ["channels", _, "users", "@me", "threads", "archived", "private"], _),
    do: [{:channels, :threads, %{}}]

  defp route(m, ["users", id], _) when m in [:get, :patch],
    do: [{:users, :one, if(id == "@me", do: %{}, else: %{"id" => id})}]

  defp route(:post, ["users", "@me", "channels"], _), do: [{:channels, :one, %{}}]

  defp route(m, ["webhooks", _, _, "messages", id], _) when m in [:get, :patch],
    do: message(:one, %{"id" => id})

  defp route(:delete, ["webhooks", _, _, "messages", id], _),
    do: [{:messages, :prune, [{{{:_, id}, :_}, [], [true]}]}]

  defp route(:post, ["webhooks", _, _], _), do: message(:one, %{})

  defp route(:get, ["guilds", g, "voice-states", id], _),
    do: [{:voice_states, :one, %{"guild_id" => g, "user_id" => id}}]

  defp route(:patch, ["guilds", g, "voice-states", id], _),
    do: [{:voice_states, :voice_delete, {g, id}}]

  defp route(_, _, _), do: []

  defp member(mode, context), do: [{:members, mode, context}, {:users, :member_users, context}]
  defp message(mode, context), do: [{:messages, mode, context}, {:users, :message_users, context}]

  defp guild_delete(g) do
    [{:guilds, :delete, g}] ++
      Enum.map([:members, :roles, :presences, :voice_states], fn r ->
        {r, :prune, [{{{g, :_}, :_}, [], [true]}]}
      end) ++
      [{:channels, :prune, [{{:_, %{guild_id: g}}, [], [true]}]}, {:messages, :guild_messages, g}]
  end
end
