defmodule Lingo.Type.IncidentsData do
  @moduledoc """
  A guild's incident actions and detections: until when invites and DMs are
  paused (see `Lingo.Api.Guild.update_incident_actions/2`), and when Discord
  last detected DM spam or a raid.
  """

  alias Lingo.Type.Parse

  @type t :: %__MODULE__{
          invites_disabled_until: DateTime.t() | nil,
          dms_disabled_until: DateTime.t() | nil,
          dm_spam_detected_at: DateTime.t() | nil,
          raid_detected_at: DateTime.t() | nil
        }

  defstruct [
    :invites_disabled_until,
    :dms_disabled_until,
    :dm_spam_detected_at,
    :raid_detected_at
  ]

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      invites_disabled_until: Parse.timestamp(data["invites_disabled_until"]),
      dms_disabled_until: Parse.timestamp(data["dms_disabled_until"]),
      dm_spam_detected_at: Parse.timestamp(data["dm_spam_detected_at"]),
      raid_detected_at: Parse.timestamp(data["raid_detected_at"])
    }
  end
end
