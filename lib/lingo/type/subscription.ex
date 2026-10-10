defmodule Lingo.Type.Subscription do
  @moduledoc """
  A user's subscription to one of the application's SKUs. `status` is
  `:active`, `:ending` (canceled, active until `current_period_end`) or
  `:inactive`.
  """

  alias Lingo.Type.Parse

  @type status :: :active | :inactive | :ending
  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          sku_ids: [String.t()],
          entitlement_ids: [String.t()],
          renewal_sku_ids: [String.t()] | nil,
          current_period_start: DateTime.t() | nil,
          current_period_end: DateTime.t() | nil,
          status: status() | integer(),
          canceled_at: DateTime.t() | nil,
          country: String.t() | nil
        }

  defstruct [
    :id,
    :user_id,
    :renewal_sku_ids,
    :current_period_start,
    :current_period_end,
    :status,
    :canceled_at,
    :country,
    sku_ids: [],
    entitlement_ids: []
  ]

  @statuses %{0 => :active, 1 => :inactive, 2 => :ending}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      user_id: data["user_id"],
      sku_ids: data["sku_ids"] || [],
      entitlement_ids: data["entitlement_ids"] || [],
      renewal_sku_ids: data["renewal_sku_ids"],
      current_period_start: Parse.timestamp(data["current_period_start"]),
      current_period_end: Parse.timestamp(data["current_period_end"]),
      status: Map.get(@statuses, data["status"], data["status"]),
      canceled_at: Parse.timestamp(data["canceled_at"]),
      country: data["country"]
    }
  end
end
