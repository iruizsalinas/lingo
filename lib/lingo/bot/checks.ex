defmodule Lingo.Bot.Checks do
  @moduledoc false

  # Runs a command's :checks and :cooldown before its handler. A check is a
  # built-in atom or tuple, or a function of the context returning true,
  # false or {:error, message}. The cooldown is counted last, so failed
  # checks don't use it up.

  alias Lingo.{CheckError, Context, Instance, Permissions}
  alias Lingo.Bot.Cooldowns

  @doc "Validates a command's checks at compile time."
  def validate!(checks) when is_list(checks) do
    for check <- checks, not valid?(check) do
      raise ArgumentError,
            "invalid check #{inspect(check)}: use :guild_only, :dm_only, :nsfw, :owner_only, " <>
              "{:permissions, list}, {:bot_permissions, list} or a function like &Mod.fun/1"
    end

    checks
  end

  def validate!(other), do: raise(ArgumentError, ":checks must be a list, got: #{inspect(other)}")

  @doc "Validates a cooldown at compile time: {uses, per_ms} or {uses, per_ms, scope}."
  def validate_cooldown!(nil), do: nil
  def validate_cooldown!({uses, per}), do: validate_cooldown!({uses, per, :user})

  def validate_cooldown!({uses, per, scope} = cooldown)
      when is_integer(uses) and uses > 0 and is_integer(per) and per > 0 and
             scope in [:user, :member, :guild, :channel, :global],
      do: cooldown

  def validate_cooldown!(other),
    do: raise(ArgumentError, "invalid :cooldown #{inspect(other)}, use {uses, per_ms, scope}")

  defp valid?(check) when check in [:guild_only, :dm_only, :nsfw, :owner_only], do: true
  defp valid?({kind, perms}) when kind in [:permissions, :bot_permissions], do: is_list(perms)
  defp valid?(fun) when is_function(fun, 1), do: Function.info(fun, :type) == {:type, :external}
  defp valid?(_check), do: false

  @spec run(%{checks: list(), cooldown: tuple() | nil}, Context.t()) ::
          :ok | {:error, CheckError.t()}
  def run(rules, ctx) do
    with :ok <- Enum.reduce_while(rules.checks, :ok, &check(&1, ctx, &2)) do
      cooldown(rules.cooldown, ctx)
    end
  end

  defp check(check, ctx, :ok) do
    case passes(check, ctx) do
      :ok -> {:cont, :ok}
      {:error, _} = error -> {:halt, error}
    end
  end

  defp passes(:guild_only, ctx), do: ok_if(ctx.guild_id != nil, :guild_only)
  defp passes(:dm_only, ctx), do: ok_if(ctx.guild_id == nil, :dm_only)

  defp passes(:nsfw, ctx),
    do: ok_if(get_in(ctx.interaction.channel || %{}, ["nsfw"]) == true, :nsfw)

  defp passes(:owner_only, ctx), do: ok_if(ctx.user_id in owner_ids(ctx.bot), :owner_only)

  defp passes({:permissions, perms}, ctx) do
    member_perms = (ctx.member && ctx.member.permissions) || "0"
    missing(member_perms, perms, :missing_permissions)
  end

  defp passes({:bot_permissions, perms}, ctx),
    do: missing(ctx.app_permissions || "0", perms, :bot_missing_permissions)

  defp passes(fun, ctx) when is_function(fun, 1) do
    case fun.(ctx) do
      true -> :ok
      {:error, message} -> {:error, CheckError.new({:check, fun}, message)}
      _false -> {:error, CheckError.new({:check, fun})}
    end
  end

  defp ok_if(true, _reason), do: :ok
  defp ok_if(false, reason), do: {:error, CheckError.new(reason)}

  # Administrator grants everything
  defp missing(bitfield, perms, reason) do
    if Permissions.has?(bitfield, :administrator) do
      :ok
    else
      case Enum.reject(perms, &Permissions.has?(bitfield, &1)) do
        [] -> :ok
        missing -> {:error, CheckError.new({reason, missing})}
      end
    end
  end

  defp cooldown(nil, _ctx), do: :ok

  defp cooldown({_uses, _per, scope} = cooldown, ctx) do
    key = {ctx.command_name, scope, scope_key(scope, ctx)}

    case Cooldowns.hit(ctx.bot, key, cooldown) do
      :ok -> :ok
      {:wait, ms} -> {:error, CheckError.new({:cooldown, ms})}
    end
  end

  defp scope_key(:user, ctx), do: ctx.user_id
  defp scope_key(:member, ctx), do: {ctx.guild_id, ctx.user_id}
  defp scope_key(:guild, ctx), do: ctx.guild_id || {:dm, ctx.channel_id}
  defp scope_key(:channel, ctx), do: ctx.channel_id
  defp scope_key(:global, _ctx), do: :global

  # the app's owner, or its team's members, fetched once
  defp owner_ids(bot) do
    case Instance.get(bot, :owner_ids, nil) do
      nil ->
        ids = fetch_owner_ids(bot)
        if ids != [], do: Instance.put(bot, :owner_ids, ids)
        ids

      ids ->
        ids
    end
  end

  defp fetch_owner_ids(bot) do
    Instance.with_current(bot, fn ->
      case Lingo.Api.Application.get_current() do
        {:ok, %{"team" => %{"members" => members}}} when is_list(members) ->
          Enum.map(members, &get_in(&1, ["user", "id"]))

        {:ok, %{"owner" => %{"id" => id}}} ->
          [id]

        _error ->
          []
      end
    end)
  end
end
