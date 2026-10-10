defmodule Lingo.Type.SKU do
  @moduledoc """
  Something the application sells. `type` is `:durable`, `:consumable`,
  `:subscription` or `:subscription_group` (the group Discord makes for a
  subscription; list its subscriptions with the `:subscription` one).
  """

  @type type :: :durable | :consumable | :subscription | :subscription_group
  @type t :: %__MODULE__{
          id: String.t(),
          type: type() | integer(),
          application_id: String.t(),
          name: String.t(),
          slug: String.t(),
          flags: integer()
        }

  defstruct [:id, :type, :application_id, :name, :slug, flags: 0]

  @types %{2 => :durable, 3 => :consumable, 5 => :subscription, 6 => :subscription_group}

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    sku = Lingo.Type.Parse.fields(__MODULE__, data)
    %{sku | type: Map.get(@types, sku.type, sku.type)}
  end
end
