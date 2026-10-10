defmodule Lingo.Type.CommandOption do
  @moduledoc "An application command option, built with `Lingo.Bot.Options`."

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
          channel_types: [Lingo.Type.Channel.channel_type() | integer()],
          file_types: [String.t()],
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
    file_types: [],
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

  @doc false
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
      channel_types:
        Enum.map(data["channel_types"] || [], &Lingo.Type.Codes.name(:channel_type, &1)),
      file_types: data["file_types"] || [],
      min_value: data["min_value"],
      max_value: data["max_value"],
      min_length: data["min_length"],
      max_length: data["max_length"],
      autocomplete: data["autocomplete"] || false
    }
  end

  @doc false
  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = opt) do
    %{
      "type" => Map.get(@option_types_reverse, opt.type, opt.type),
      "name" => opt.name,
      "description" => opt.description,
      "required" => opt.required
    }
    |> put_if("name_localizations", opt.name_localizations)
    |> put_if("description_localizations", opt.description_localizations)
    |> put_if("choices", non_empty(opt.choices))
    |> put_if("options", non_empty_map(opt.options, &to_payload/1))
    |> put_if(
      "channel_types",
      non_empty(Enum.map(opt.channel_types, &Lingo.Type.Codes.code(:channel_type, &1)))
    )
    |> put_if("file_types", non_empty(opt.file_types))
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
