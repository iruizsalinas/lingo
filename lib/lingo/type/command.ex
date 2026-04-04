defmodule Lingo.Type.ApplicationCommand do
  @moduledoc false

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

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      type: Map.get(@command_types, data["type"], :chat_input),
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
      version: data["version"],
      integration_types: data["integration_types"],
      contexts: data["contexts"]
    }
  end

  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = cmd) do
    payload = %{
      "name" => cmd.name,
      "description" => cmd.description,
      "type" => Map.get(@command_types_reverse, cmd.type, 1),
      "options" => Enum.map(cmd.options, &Lingo.Type.CommandOption.to_payload/1)
    }

    payload
    |> put_if("name_localizations", cmd.name_localizations)
    |> put_if("description_localizations", cmd.description_localizations)
    |> put_if("default_member_permissions", cmd.default_member_permissions)
    |> put_if("dm_permission", if(cmd.dm_permission == true, do: nil, else: cmd.dm_permission))
    |> put_if("nsfw", if(cmd.nsfw, do: true, else: nil))
    |> put_if("integration_types", cmd.integration_types)
    |> put_if("contexts", cmd.contexts)
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end

defmodule Lingo.Type.CommandOption do
  @moduledoc false

  @type option_type ::
          :sub_command
          | :sub_command_group
          | :string
          | :integer
          | :boolean
          | :user
          | :channel
          | :role
          | :mentionable
          | :number
          | :attachment

  @type t :: %__MODULE__{
          type: option_type(),
          name: String.t(),
          name_localizations: map() | nil,
          description: String.t(),
          description_localizations: map() | nil,
          required: boolean(),
          choices: [map()],
          options: [t()],
          channel_types: [integer()],
          min_value: number() | nil,
          max_value: number() | nil,
          min_length: integer() | nil,
          max_length: integer() | nil,
          autocomplete: boolean()
        }

  defstruct [
    :type,
    :name,
    :name_localizations,
    :description,
    :description_localizations,
    :min_value,
    :max_value,
    :min_length,
    :max_length,
    required: false,
    choices: [],
    options: [],
    channel_types: [],
    autocomplete: false
  ]

  @option_types %{
    1 => :sub_command,
    2 => :sub_command_group,
    3 => :string,
    4 => :integer,
    5 => :boolean,
    6 => :user,
    7 => :channel,
    8 => :role,
    9 => :mentionable,
    10 => :number,
    11 => :attachment
  }

  @option_types_reverse Map.new(@option_types, fn {k, v} -> {v, k} end)

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      type: Map.get(@option_types, data["type"], data["type"]),
      name: data["name"],
      name_localizations: data["name_localizations"],
      description: data["description"] || "",
      description_localizations: data["description_localizations"],
      required: data["required"] || false,
      choices: data["choices"] || [],
      options: (data["options"] || []) |> Enum.map(&new/1),
      channel_types: data["channel_types"] || [],
      min_value: data["min_value"],
      max_value: data["max_value"],
      min_length: data["min_length"],
      max_length: data["max_length"],
      autocomplete: data["autocomplete"] || false
    }
  end

  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = opt) do
    %{
      "type" => Map.fetch!(@option_types_reverse, opt.type),
      "name" => opt.name,
      "description" => opt.description,
      "required" => opt.required
    }
    |> put_if("name_localizations", opt.name_localizations)
    |> put_if("description_localizations", opt.description_localizations)
    |> put_if("choices", non_empty(opt.choices))
    |> put_if("options", non_empty_map(opt.options, &to_payload/1))
    |> put_if("channel_types", non_empty(opt.channel_types))
    |> put_if("min_value", opt.min_value)
    |> put_if("max_value", opt.max_value)
    |> put_if("min_length", opt.min_length)
    |> put_if("max_length", opt.max_length)
    |> put_if("autocomplete", if(opt.autocomplete, do: true, else: nil))
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp non_empty([]), do: nil
  defp non_empty(list), do: list

  defp non_empty_map([], _fun), do: nil
  defp non_empty_map(list, fun), do: Enum.map(list, fun)
end
