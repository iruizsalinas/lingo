defmodule Lingo.Context.Input do
  @moduledoc false

  # Reading command options and modal fields. Public through Lingo.Context.

  alias Lingo.Context
  alias Lingo.Context.{Parse, Resolved}
  alias Lingo.Type.{Attachment, Channel, Member, Role, User}

  @type name :: atom() | String.t()

  @spec option(Context.t(), name()) :: term()
  def option(%Context{options: options}, name) when is_atom(name) do
    case Map.fetch(options, name) do
      {:ok, value} -> value
      :error -> Map.get(options, Atom.to_string(name))
    end
  end

  def option(%Context{options: options}, name) when is_binary(name) do
    case Map.fetch(options, name) do
      {:ok, value} ->
        value

      :error ->
        case Parse.existing_atom(name) do
          {:ok, atom} -> Map.get(options, atom)
          :error -> nil
        end
    end
  end

  @spec modal_value(Context.t(), name()) :: term()
  def modal_value(ctx, field_id), do: option(ctx, field_id)

  @spec focused_option(Context.t()) :: {name(), term()} | nil
  def focused_option(%Context{raw_options: options}), do: Parse.focused(options)

  @spec get_user(Context.t(), name()) :: User.t() | nil
  def get_user(ctx, name), do: resolve(ctx, name, &Resolved.resolved_user/2)

  @spec get_member(Context.t(), name()) :: Member.t() | nil
  def get_member(ctx, name), do: resolve(ctx, name, &Resolved.resolved_member/2)

  @spec get_role(Context.t(), name()) :: Role.t() | nil
  def get_role(ctx, name), do: resolve(ctx, name, &Resolved.resolved_role/2)

  @spec get_channel(Context.t(), name()) :: Channel.t() | nil
  def get_channel(ctx, name), do: resolve(ctx, name, &Resolved.resolved_channel/2)

  @spec get_attachment(Context.t(), name()) :: Attachment.t() | nil
  def get_attachment(ctx, name), do: resolve(ctx, name, &Resolved.resolved_attachment/2)

  defp resolve(ctx, name, resolver) do
    case option(ctx, name) do
      nil -> nil
      id -> resolver.(ctx, id)
    end
  end
end
