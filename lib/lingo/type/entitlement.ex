defmodule Lingo.Type.Entitlement do
  @moduledoc false

  @type entitlement_type ::
          :purchase
          | :premium_subscription
          | :developer_gift
          | :test_mode_purchase
          | :free_purchase
          | :user_gift
          | :premium_purchase
          | :application_subscription
  @type t :: %__MODULE__{
          id: String.t(),
          sku_id: String.t(),
          application_id: String.t(),
          user_id: String.t() | nil,
          guild_id: String.t() | nil,
          type: entitlement_type(),
          deleted: boolean(),
          starts_at: String.t() | nil,
          ends_at: String.t() | nil,
          consumed: boolean(),
          subscription_id: String.t() | nil
        }

  defstruct [
    :id,
    :sku_id,
    :application_id,
    :user_id,
    :guild_id,
    :type,
    :starts_at,
    :ends_at,
    :subscription_id,
    deleted: false,
    consumed: false
  ]

  @types %{
    1 => :purchase,
    2 => :premium_subscription,
    3 => :developer_gift,
    4 => :test_mode_purchase,
    5 => :free_purchase,
    6 => :user_gift,
    7 => :premium_purchase,
    8 => :application_subscription
  }

  def new(nil), do: nil

  def new(data) when is_map(data) do
    %__MODULE__{
      id: data["id"],
      sku_id: data["sku_id"],
      application_id: data["application_id"],
      user_id: data["user_id"],
      guild_id: data["guild_id"],
      type: Map.get(@types, data["type"], data["type"]),
      deleted: data["deleted"] || false,
      starts_at: data["starts_at"],
      ends_at: data["ends_at"],
      consumed: data["consumed"] || false,
      subscription_id: data["subscription_id"]
    }
  end
end
