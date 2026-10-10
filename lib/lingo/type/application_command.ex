defmodule Lingo.Type.ApplicationCommand do
  @moduledoc "An application command, as declared with `Lingo.Bot.Commands.command/3` or returned by Discord."

  @type command_type :: :chat_input | :user | :message | :primary_entry_point

  @type t :: %__MODULE__{
          id: String.t() | nil,
          type: command_type(),
          application_id: String.t() | nil,
          guild_id: String.t() | nil,
          name: String.t(),
          name_localizations: map() | nil,
          description: String.t(),
          description_localizations: map() | nil,
          options: [Lingo.Type.CommandOption.t()],
          default_member_permissions: String.t() | nil,
          dm_permission: boolean(),
          nsfw: boolean(),
          handler: integer() | nil,
          version: String.t() | nil,
          integration_types: [integer()] | nil,
          contexts: [integer()] | nil
        }

  defstruct [
    :id,
    :application_id,
    :guild_id,
    :name,
    :name_localizations,
    :description,
    :description_localizations,
    :default_member_permissions,
    :handler,
    :version,
    :integration_types,
    :contexts,
    type: :chat_input,
    options: [],
    dm_permission: true,
    nsfw: false
  ]

  @command_types %{1 => :chat_input, 2 => :user, 3 => :message, 4 => :primary_entry_point}
  @command_types_reverse %{chat_input: 1, user: 2, message: 3, primary_entry_point: 4}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      type: Map.get(@command_types, data["type"], data["type"] || :chat_input),
      application_id: data["application_id"],
      guild_id: data["guild_id"],
      name: data["name"],
      name_localizations: data["name_localizations"],
      description: data["description"] || "",
      description_localizations: data["description_localizations"],
      options: (data["options"] || []) |> Enum.map(&Lingo.Type.CommandOption.new/1),
      default_member_permissions: data["default_member_permissions"],
      dm_permission: data["dm_permission"] != false,
      nsfw: data["nsfw"] || false,
      handler: data["handler"],
      version: data["version"],
      integration_types: data["integration_types"],
      contexts: data["contexts"]
    }
  end

  @doc false
  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = cmd) do
    payload =
      %{
        "name" => cmd.name,
        "type" => Map.get(@command_types_reverse, cmd.type, cmd.type)
      }
      |> maybe_put_command_body(cmd)

    payload
    |> put_if("name_localizations", cmd.name_localizations)
    |> put_if("description_localizations", cmd.description_localizations)
    |> put_if("default_member_permissions", permissions_string(cmd.default_member_permissions))
    |> put_if("dm_permission", if(cmd.dm_permission == true, do: nil, else: cmd.dm_permission))
    |> put_if("nsfw", if(cmd.nsfw, do: true, else: nil))
    |> maybe_put_handler(cmd)
    |> put_if("integration_types", cmd.integration_types)
    |> put_if("contexts", cmd.contexts)
  end

  defp maybe_put_command_body(payload, %{type: type} = cmd)
       when type in [:chat_input, :primary_entry_point] do
    payload
    |> put_if("description", cmd.description)
    |> put_if("options", non_empty_map(cmd.options, &Lingo.Type.CommandOption.to_payload/1))
  end

  defp maybe_put_command_body(payload, _cmd), do: payload

  defp maybe_put_handler(payload, %{type: :primary_entry_point, handler: handler}) do
    put_if(payload, "handler", handler)
  end

  defp maybe_put_handler(payload, _cmd), do: payload

  # Discord types this as a string bitfield
  defp permissions_string(perms) when is_integer(perms), do: Integer.to_string(perms)
  defp permissions_string(perms), do: perms

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp non_empty_map([], _fun), do: nil
  defp non_empty_map(list, fun), do: Enum.map(list, fun)
end
