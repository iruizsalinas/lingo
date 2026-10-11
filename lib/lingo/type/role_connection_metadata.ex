defmodule Lingo.Type.RoleConnectionMetadata do
  @moduledoc """
  One of the application's role connection metadata records: a value users
  carry (see `Lingo.OAuth2.update_role_connection/3`) that guilds compare
  against to grant linked roles.

  `type` is the comparison: `:integer_less_than_or_equal`,
  `:integer_greater_than_or_equal`, `:integer_equal`, `:integer_not_equal`,
  `:datetime_less_than_or_equal`, `:datetime_greater_than_or_equal`,
  `:boolean_equal` or `:boolean_not_equal`.
  """

  @type metadata_type ::
          :integer_less_than_or_equal
          | :integer_greater_than_or_equal
          | :integer_equal
          | :integer_not_equal
          | :datetime_less_than_or_equal
          | :datetime_greater_than_or_equal
          | :boolean_equal
          | :boolean_not_equal
  @type t :: %__MODULE__{
          type: metadata_type() | integer(),
          key: String.t(),
          name: String.t(),
          name_localizations: %{String.t() => String.t()} | nil,
          description: String.t(),
          description_localizations: %{String.t() => String.t()} | nil
        }

  defstruct [:type, :key, :name, :name_localizations, :description, :description_localizations]

  @types %{
    1 => :integer_less_than_or_equal,
    2 => :integer_greater_than_or_equal,
    3 => :integer_equal,
    4 => :integer_not_equal,
    5 => :datetime_less_than_or_equal,
    6 => :datetime_greater_than_or_equal,
    7 => :boolean_equal,
    8 => :boolean_not_equal
  }

  @doc false
  def new(nil), do: nil

  def new(data) when is_map(data) do
    metadata = Lingo.Type.Parse.fields(__MODULE__, data)
    %{metadata | type: Map.get(@types, metadata.type, metadata.type)}
  end
end
