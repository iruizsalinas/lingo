defmodule Lingo.Gateway.Payload do
  @moduledoc false

  @spec identify(String.t(), integer(), integer(), integer(), keyword()) :: map()
  def identify(token, intents, shard_id, shard_count, presence \\ []) do
    d = %{
      "token" => token,
      "intents" => intents,
      "properties" => %{
        "os" => to_string(:os.type() |> elem(0)),
        "browser" => "lingo",
        "device" => "lingo"
      },
      "compress" => false,
      "large_threshold" => 250,
      "shard" => [shard_id, shard_count]
    }

    d =
      if presence != [] do
        Map.put(d, "presence", build_presence(presence))
      else
        d
      end

    %{"op" => 2, "d" => d}
  end

  defp build_presence(opts) do
    status = Keyword.get(opts, :status, :online)
    text = Keyword.get(opts, :text)
    activity = Keyword.get(opts, :activity)

    activities =
      cond do
        activity -> [Lingo.Type.Activity.to_payload(activity)]
        text -> [%{"name" => text, "type" => 0}]
        true -> []
      end

    %{
      "since" => if(status == :idle, do: System.system_time(:millisecond), else: nil),
      "activities" => activities,
      "status" => to_string(status),
      "afk" => status == :idle
    }
  end

  @spec resume(String.t(), String.t(), integer()) :: map()
  def resume(token, session_id, seq) do
    %{
      "op" => 6,
      "d" => %{
        "token" => token,
        "session_id" => session_id,
        "seq" => seq
      }
    }
  end

  @spec heartbeat(integer() | nil) :: map()
  def heartbeat(seq) do
    %{"op" => 1, "d" => seq}
  end

  @spec presence_update(atom(), String.t() | nil, Lingo.Type.Activity.t() | nil) :: map()
  def presence_update(status, text \\ nil, activity \\ nil) do
    activities =
      if activity do
        [Lingo.Type.Activity.to_payload(activity)]
      else
        if text do
          [%{"name" => text, "type" => 0}]
        else
          []
        end
      end

    %{
      "op" => 3,
      "d" => %{
        "since" => if(status == :idle, do: System.system_time(:millisecond), else: nil),
        "activities" => activities,
        "status" => to_string(status),
        "afk" => status == :idle
      }
    }
  end

  @spec voice_state_update(String.t(), String.t() | nil, keyword()) :: map()
  def voice_state_update(guild_id, channel_id, opts \\ []) do
    %{
      "op" => 4,
      "d" => %{
        "guild_id" => guild_id,
        "channel_id" => channel_id,
        "self_mute" => opts[:self_mute] || false,
        "self_deaf" => opts[:self_deaf] || false
      }
    }
  end

  @spec request_guild_members(String.t(), keyword()) :: map()
  def request_guild_members(guild_id, opts \\ []) do
    d = %{"guild_id" => guild_id}

    d =
      cond do
        opts[:user_ids] ->
          Map.put(d, "user_ids", opts[:user_ids])

        opts[:query] != nil ->
          Map.merge(d, %{"query" => opts[:query], "limit" => opts[:limit] || 0})

        true ->
          Map.merge(d, %{"query" => "", "limit" => opts[:limit] || 0})
      end

    d = if opts[:presences], do: Map.put(d, "presences", true), else: d
    d = if opts[:nonce], do: Map.put(d, "nonce", opts[:nonce]), else: d

    %{"op" => 8, "d" => d}
  end

  @spec request_soundboard_sounds([String.t()]) :: map()
  def request_soundboard_sounds(guild_ids) when is_list(guild_ids) do
    %{"op" => 31, "d" => %{"guild_ids" => guild_ids}}
  end

  @spec encode(map()) :: binary()
  def encode(payload), do: Jason.encode!(payload)

  @spec decode(binary()) :: map()
  def decode(data), do: Jason.decode!(data)
end
