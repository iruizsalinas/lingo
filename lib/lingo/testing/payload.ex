defmodule Lingo.Testing.Payload do
  @moduledoc false

  # Interaction payloads as Discord sends them, for Lingo.Testing. Command
  # options are typed from the bot's declared commands.

  alias Lingo.Instance
  alias Lingo.Type.CommandOption

  def command(name, opts) do
    type = Keyword.get(opts, :type, :chat_input)
    declared = declared_command(name, type)
    options = build_options(Keyword.get(opts, :options, []), declared.options || [])

    %{"id" => id(), "name" => name, "type" => command_type(type), "options" => options}
    |> put_if("target_id", opts[:target_id])
  end

  def autocomplete(name, opts) do
    focused = to_string(Keyword.fetch!(opts, :focused))

    options =
      Enum.map(command(name, opts)["options"], fn
        %{"name" => ^focused} = option -> Map.put(option, "focused", true)
        option -> option
      end)

    %{"id" => id(), "name" => name, "type" => 1, "options" => options}
  end

  def component(custom_id, opts) do
    values = Keyword.get(opts, :values)

    data =
      %{"custom_id" => custom_id, "component_type" => if(values, do: 3, else: 2)}
      |> put_if("values", values)

    {data, %{"id" => Keyword.get(opts, :message_id, id()), "channel_id" => channel(opts)}}
  end

  def modal(custom_id, values) do
    components =
      for {input_id, value} <- values,
          do: %{
            "type" => 18,
            "component" => %{"type" => 4, "custom_id" => input_id, "value" => value}
          }

    %{"custom_id" => custom_id, "components" => components}
  end

  def interaction(type, data, opts) do
    user = %{"id" => Keyword.get(opts, :user_id, "1"), "username" => "tester"}

    %{
      "id" => id(),
      "application_id" => "100",
      "type" => type,
      "token" => "token-#{id()}",
      "version" => 1,
      "channel_id" => channel(opts),
      "locale" => Keyword.get(opts, :locale, "en-US"),
      "app_permissions" => to_string(Keyword.get(opts, :app_permissions, 0)),
      "data" => data
    }
    |> put_if("message", opts[:message])
    |> put_user(user, Keyword.get(opts, :guild_id, "2"), opts)
  end

  defp put_user(payload, user, nil, _opts), do: Map.put(payload, "user", user)

  defp put_user(payload, user, guild_id, opts) do
    permissions = to_string(Keyword.get(opts, :permissions, 0))
    member = %{"user" => user, "roles" => [], "permissions" => permissions}
    Map.merge(payload, %{"guild_id" => guild_id, "member" => member})
  end

  defp declared_command(name, type) do
    bot = Instance.get(:bot)

    Enum.find(bot.__commands__(), &(&1.name == name and &1.type == type)) ||
      raise ArgumentError, "#{inspect(bot)} declares no #{type} command #{inspect(name)}"
  end

  defp build_options(given, declared) do
    for {name, value} <- given do
      option =
        Enum.find(declared, &(&1.name == to_string(name))) ||
          raise ArgumentError, "no option #{inspect(name)} declared"

      payload = %{"name" => option.name, "type" => CommandOption.to_payload(option)["type"]}

      if option.type in [:sub_command, :sub_command_group],
        do: Map.put(payload, "options", build_options(value, option.options || [])),
        else: Map.put(payload, "value", value)
    end
  end

  defp command_type(:chat_input), do: 1
  defp command_type(:user), do: 2
  defp command_type(:message), do: 3

  defp channel(opts), do: Keyword.get(opts, :channel_id, "3")
  defp id, do: Integer.to_string(System.unique_integer([:positive]) + 1_000_000_000_000_000)

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
