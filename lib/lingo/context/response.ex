defmodule Lingo.Context.Response do
  @moduledoc false

  # Answering interactions. The public functions are on Lingo.Context.

  import Bitwise

  alias Lingo.Api.Interaction, as: Api
  alias Lingo.Context

  @ephemeral 1 <<< 6

  @type content :: String.t() | keyword() | map()
  @type result :: {:ok, Context.t()} | {:error, Lingo.Error.t()}

  @spec reply(Context.t(), content()) :: result()
  def reply(%Context{deferred: true} = ctx, content) do
    # ephemerality is fixed by the defer, and edits reject the EPHEMERAL flag
    in_bot(ctx, fn ->
      Api.update_original_response(ctx.interaction_token, drop_ephemeral(data(content)))
    end)
    |> answered(%{ctx | deferred: false, replied: true})
  end

  def reply(%Context{replied: true} = ctx, content),
    do:
      in_bot(ctx, fn -> Api.create_followup(ctx.interaction_token, data(content)) end)
      |> answered(ctx)

  def reply(ctx, content), do: respond(ctx, :channel_message, data(content))

  @spec ephemeral(Context.t(), content()) :: result()
  def ephemeral(ctx, content),
    do: reply(ctx, Map.update(data(content), :flags, @ephemeral, &bor(&1 || 0, @ephemeral)))

  @spec update(Context.t(), content()) :: result()
  def update(%Context{deferred: true} = ctx, content) do
    in_bot(ctx, fn -> Api.update_original_response(ctx.interaction_token, data(content)) end)
    |> answered(%{ctx | deferred: false, replied: true})
  end

  def update(ctx, content), do: respond(ctx, :update_message, data(content))

  @spec defer(Context.t(), keyword()) :: result()
  def defer(ctx, opts \\ [])
  def defer(%Context{deferred: true} = ctx, _opts), do: {:ok, ctx}

  def defer(ctx, opts) do
    type = if opts[:update], do: :deferred_update_message, else: :deferred_channel_message
    flags = if opts[:ephemeral], do: %{flags: @ephemeral}

    in_bot(ctx, fn ->
      Api.create_response(ctx.interaction_id, ctx.interaction_token, type, flags)
    end)
    |> answered(%{ctx | deferred: true})
  end

  @spec show_modal(Context.t(), map()) :: result()
  def show_modal(ctx, modal), do: respond(ctx, :modal, modal)

  @spec autocomplete_result(Context.t(), [map() | keyword()]) :: result()
  def autocomplete_result(ctx, choices) when is_list(choices),
    do: respond(ctx, :autocomplete, %{choices: Enum.map(choices, &Map.new/1)})

  def reply!(ctx, content), do: ctx |> reply(content) |> unwrap!()
  def ephemeral!(ctx, content), do: ctx |> ephemeral(content) |> unwrap!()
  def update!(ctx, content), do: ctx |> update(content) |> unwrap!()
  def defer!(ctx, opts \\ []), do: ctx |> defer(opts) |> unwrap!()
  def show_modal!(ctx, modal), do: ctx |> show_modal(modal) |> unwrap!()
  def autocomplete_result!(ctx, choices), do: ctx |> autocomplete_result(choices) |> unwrap!()

  defp respond(ctx, type, data) do
    in_bot(ctx, fn ->
      Api.create_response(ctx.interaction_id, ctx.interaction_token, type, data)
    end)
    |> answered(%{ctx | replied: true})
  end

  defp answered(:ok, ctx), do: {:ok, ctx}
  defp answered({:ok, _response}, ctx), do: {:ok, ctx}
  defp answered({:error, _} = error, _ctx), do: error

  # a context answers for its own bot, from any process
  defp in_bot(%Context{bot: bot}, fun), do: Lingo.Instance.with_current(bot, fun)

  defp unwrap!({:ok, ctx}), do: ctx
  defp unwrap!({:error, error}) when is_exception(error), do: raise(error)

  defp data(content) when is_binary(content), do: %{content: content}
  defp data(content) when is_list(content), do: Map.new(content)
  defp data(content) when is_map(content), do: content

  defp drop_ephemeral(%{flags: flags} = data) when is_integer(flags) do
    case band(flags, bnot(@ephemeral)) do
      0 -> Map.delete(data, :flags)
      rest -> %{data | flags: rest}
    end
  end

  defp drop_ephemeral(data), do: data
end
