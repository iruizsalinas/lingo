defmodule Lingo.Command.Context do
  @moduledoc false

  alias Lingo.Api.Interaction, as: InteractionApi

  @type t :: %__MODULE__{
          interaction_id: String.t(),
          interaction_token: String.t(),
          application_id: String.t(),
          guild_id: String.t() | nil,
          channel_id: String.t() | nil,
          user_id: String.t() | nil,
          member: Lingo.Type.Member.t() | nil,
          user: Lingo.Type.User.t() | nil,
          command_name: String.t() | nil,
          options: %{atom() => any()},
          raw_options: [map()] | nil,
          resolved: map() | nil,
          replied: boolean(),
          deferred: boolean(),
          custom_id: String.t() | nil,
          values: [String.t()],
          target_id: String.t() | nil,
          message: Lingo.Type.Message.t() | nil,
          component_type: integer() | nil
        }

  defstruct [
    :interaction_id,
    :interaction_token,
    :application_id,
    :guild_id,
    :channel_id,
    :user_id,
    :member,
    :user,
    :command_name,
    :resolved,
    :raw_options,
    :target_id,
    :custom_id,
    :message,
    :component_type,
    options: %{},
    replied: false,
    deferred: false,
    values: []
  ]

  @spec from_interaction(Lingo.Type.Interaction.t()) :: t()
  def from_interaction(%Lingo.Type.Interaction{} = i) do
    user = Lingo.Type.Interaction.author(i)

    %__MODULE__{
      interaction_id: i.id,
      interaction_token: i.token,
      application_id: i.application_id,
      guild_id: i.guild_id,
      channel_id: i.channel_id,
      user_id: user && user.id,
      member: i.member,
      user: user,
      command_name: get_in(i.data, ["name"]),
      options: parse_options(i.data["options"]),
      raw_options: i.data["options"],
      resolved: i.data["resolved"],
      target_id: get_in(i.data, ["target_id"])
    }
  end

  @spec from_component(Lingo.Type.Interaction.t()) :: t()
  def from_component(%Lingo.Type.Interaction{} = i) do
    user = Lingo.Type.Interaction.author(i)

    %__MODULE__{
      interaction_id: i.id,
      interaction_token: i.token,
      application_id: i.application_id,
      guild_id: i.guild_id,
      channel_id: i.channel_id,
      user_id: user && user.id,
      member: i.member,
      user: user,
      custom_id: get_in(i.data, ["custom_id"]),
      values: get_in(i.data, ["values"]) || [],
      component_type: get_in(i.data, ["component_type"]),
      message: i.message,
      resolved: get_in(i.data, ["resolved"])
    }
  end

  @spec from_modal(Lingo.Type.Interaction.t()) :: t()
  def from_modal(%Lingo.Type.Interaction{} = i) do
    user = Lingo.Type.Interaction.author(i)

    %__MODULE__{
      interaction_id: i.id,
      interaction_token: i.token,
      application_id: i.application_id,
      guild_id: i.guild_id,
      channel_id: i.channel_id,
      user_id: user && user.id,
      member: i.member,
      user: user,
      custom_id: get_in(i.data, ["custom_id"]),
      options: parse_modal_components(get_in(i.data, ["components"])),
      resolved: get_in(i.data, ["resolved"])
    }
  end

  @spec option(t(), atom() | String.t()) :: any()
  def option(%__MODULE__{options: options}, name) when is_atom(name) do
    Map.get(options, name)
  end

  def option(%__MODULE__{options: options}, name) when is_binary(name) do
    Map.get(options, String.to_existing_atom(name))
  rescue
    ArgumentError -> nil
  end

  @spec modal_value(t(), atom() | String.t()) :: any()
  def modal_value(ctx, field_id), do: option(ctx, field_id)

  @spec resolved_user(t(), String.t()) :: Lingo.Type.User.t() | nil
  def resolved_user(%__MODULE__{resolved: r}, user_id) when is_map(r) do
    case get_in(r, ["users", user_id]) do
      nil -> nil
      data -> Lingo.Type.User.new(data)
    end
  end

  def resolved_user(_, _), do: nil

  @spec resolved_member(t(), String.t()) :: Lingo.Type.Member.t() | nil
  def resolved_member(%__MODULE__{resolved: r}, user_id) when is_map(r) do
    case get_in(r, ["members", user_id]) do
      nil -> nil
      data -> Lingo.Type.Member.new(data)
    end
  end

  def resolved_member(_, _), do: nil

  @spec resolved_role(t(), String.t()) :: Lingo.Type.Role.t() | nil
  def resolved_role(%__MODULE__{resolved: r}, role_id) when is_map(r) do
    case get_in(r, ["roles", role_id]) do
      nil -> nil
      data -> Lingo.Type.Role.new(data)
    end
  end

  def resolved_role(_, _), do: nil

  @spec resolved_channel(t(), String.t()) :: Lingo.Type.Channel.t() | nil
  def resolved_channel(%__MODULE__{resolved: r}, channel_id) when is_map(r) do
    case get_in(r, ["channels", channel_id]) do
      nil -> nil
      data -> Lingo.Type.Channel.new(data)
    end
  end

  def resolved_channel(_, _), do: nil

  @spec resolved_message(t(), String.t()) :: Lingo.Type.Message.t() | nil
  def resolved_message(%__MODULE__{resolved: r}, message_id) when is_map(r) do
    case get_in(r, ["messages", message_id]) do
      nil -> nil
      data -> Lingo.Type.Message.new(data)
    end
  end

  def resolved_message(_, _), do: nil

  @spec resolved_attachment(t(), String.t()) :: Lingo.Type.Attachment.t() | nil
  def resolved_attachment(%__MODULE__{resolved: r}, attachment_id) when is_map(r) do
    case get_in(r, ["attachments", attachment_id]) do
      nil -> nil
      data -> Lingo.Type.Attachment.new(data)
    end
  end

  def resolved_attachment(_, _), do: nil

  @spec get_user(t(), atom() | String.t()) :: Lingo.Type.User.t() | nil
  def get_user(ctx, option_name) do
    case option(ctx, option_name) do
      nil -> nil
      user_id -> resolved_user(ctx, user_id)
    end
  end

  @spec get_role(t(), atom() | String.t()) :: Lingo.Type.Role.t() | nil
  def get_role(ctx, option_name) do
    case option(ctx, option_name) do
      nil -> nil
      role_id -> resolved_role(ctx, role_id)
    end
  end

  @spec get_channel(t(), atom() | String.t()) :: Lingo.Type.Channel.t() | nil
  def get_channel(ctx, option_name) do
    case option(ctx, option_name) do
      nil -> nil
      channel_id -> resolved_channel(ctx, channel_id)
    end
  end

  @spec get_member(t(), atom() | String.t()) :: Lingo.Type.Member.t() | nil
  def get_member(ctx, option_name) do
    case option(ctx, option_name) do
      nil -> nil
      user_id -> resolved_member(ctx, user_id)
    end
  end

  @spec reply(t(), String.t() | map()) :: {:ok, t()} | {:error, any()}
  def reply(ctx, content) when is_binary(content) do
    reply(ctx, %{content: content})
  end

  def reply(ctx, data) when not is_binary(data) do
    cond do
      ctx.deferred ->
        case InteractionApi.edit_original_response(
               ctx.application_id,
               ctx.interaction_token,
               data
             ) do
          {:ok, _} -> {:ok, %{ctx | replied: true}}
          error -> error
        end

      ctx.replied ->
        case InteractionApi.create_followup(ctx.application_id, ctx.interaction_token, data) do
          {:ok, _} -> {:ok, ctx}
          error -> error
        end

      true ->
        case InteractionApi.create_response(
               ctx.interaction_id,
               ctx.interaction_token,
               :channel_message,
               data
             ) do
          :ok -> {:ok, %{ctx | replied: true}}
          {:ok, _} -> {:ok, %{ctx | replied: true}}
          error -> error
        end
    end
  end

  @spec reply!(t(), String.t() | map()) :: t()
  def reply!(ctx, content) do
    case reply(ctx, content) do
      {:ok, ctx} -> ctx
      {:error, reason} -> raise "Failed to reply: #{inspect(reason)}"
    end
  end

  @spec update(t(), String.t() | map()) :: {:ok, t()} | {:error, any()}
  def update(ctx, content) when is_binary(content), do: update(ctx, %{content: content})

  def update(ctx, data) when is_map(data) do
    case InteractionApi.create_response(
           ctx.interaction_id,
           ctx.interaction_token,
           :update_message,
           data
         ) do
      :ok -> {:ok, %{ctx | replied: true}}
      {:ok, _} -> {:ok, %{ctx | replied: true}}
      error -> error
    end
  end

  @spec update!(t(), String.t() | map()) :: t()
  def update!(ctx, content) do
    case update(ctx, content) do
      {:ok, ctx} -> ctx
      {:error, reason} -> raise "Failed to update message: #{inspect(reason)}"
    end
  end

  @spec defer(t(), keyword()) :: {:ok, t()} | {:error, any()}
  def defer(ctx, opts \\ []) do
    if ctx.deferred, do: {:ok, ctx}, else: do_defer(ctx, opts)
  end

  defp do_defer(ctx, opts) do
    type = if opts[:update], do: :deferred_update_message, else: :deferred_channel_message
    flags = if opts[:ephemeral], do: %{flags: 64}, else: nil

    case InteractionApi.create_response(ctx.interaction_id, ctx.interaction_token, type, flags) do
      :ok -> {:ok, %{ctx | deferred: true}}
      {:ok, _} -> {:ok, %{ctx | deferred: true}}
      error -> error
    end
  end

  @spec defer!(t(), keyword()) :: t()
  def defer!(ctx, opts \\ []) do
    case defer(ctx, opts) do
      {:ok, ctx} -> ctx
      {:error, reason} -> raise "Failed to defer: #{inspect(reason)}"
    end
  end

  @spec ephemeral(t(), String.t() | map()) :: {:ok, t()} | {:error, any()}
  def ephemeral(ctx, content) when is_binary(content) do
    reply(ctx, %{content: content, flags: 64})
  end

  def ephemeral(ctx, data) when is_map(data) do
    reply(ctx, Map.put(data, :flags, 64))
  end

  @spec show_modal(t(), map()) :: :ok | {:ok, any()} | {:error, any()}
  def show_modal(ctx, modal_data) do
    InteractionApi.create_response(ctx.interaction_id, ctx.interaction_token, :modal, modal_data)
  end

  @spec show_modal!(t(), map()) :: :ok
  def show_modal!(ctx, modal_data) do
    case show_modal(ctx, modal_data) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> raise "Failed to show modal: #{inspect(reason)}"
    end
  end

  @spec autocomplete_result(t(), [map()]) :: :ok | {:ok, any()} | {:error, any()}
  def autocomplete_result(ctx, choices) when is_list(choices) do
    InteractionApi.create_response(
      ctx.interaction_id,
      ctx.interaction_token,
      :autocomplete,
      %{choices: choices}
    )
  end

  @spec focused_option(t()) :: {String.t(), any()} | nil
  def focused_option(%__MODULE__{} = ctx) do
    ctx.raw_options |> find_focused()
  end

  defp find_focused(nil), do: nil
  defp find_focused([]), do: nil

  defp find_focused([%{"focused" => true, "name" => name, "value" => value} | _]) do
    {name, value}
  end

  defp find_focused([%{"options" => nested} | _]) when is_list(nested) do
    find_focused(nested)
  end

  defp find_focused([_ | rest]), do: find_focused(rest)

  defp parse_options(nil), do: %{}

  defp parse_options(options) when is_list(options) do
    Enum.reduce(options, %{}, fn opt, acc ->
      case opt do
        %{"type" => type, "name" => name} when type in [1, 2] ->
          sub_opts = parse_options(opt["options"])
          Map.put(acc, safe_to_atom(name), sub_opts)

        %{"name" => name, "value" => value} ->
          Map.put(acc, safe_to_atom(name), value)

        _ ->
          acc
      end
    end)
  end

  defp parse_modal_components(nil), do: %{}

  defp parse_modal_components(components) when is_list(components) do
    Enum.reduce(components, %{}, fn comp, acc ->
      extract_modal_value(comp, acc)
    end)
  end

  defp extract_modal_value(%{"type" => 1, "components" => children}, acc)
       when is_list(children) do
    Enum.reduce(children, acc, &extract_modal_value/2)
  end

  defp extract_modal_value(%{"type" => 18, "component" => child}, acc)
       when is_map(child) do
    extract_modal_value(child, acc)
  end

  defp extract_modal_value(%{"custom_id" => cid, "value" => value}, acc) do
    Map.put(acc, safe_to_atom(cid), value)
  end

  defp extract_modal_value(%{"custom_id" => cid, "values" => values}, acc)
       when is_list(values) do
    Map.put(acc, safe_to_atom(cid), values)
  end

  defp extract_modal_value(_comp, acc), do: acc

  defp safe_to_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> String.to_atom(str)
  end
end
