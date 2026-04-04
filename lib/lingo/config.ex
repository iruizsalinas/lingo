defmodule Lingo.Config do
  @moduledoc false

  def put(key, value), do: :persistent_term.put({:lingo, key}, value)

  def get(key), do: :persistent_term.get({:lingo, key}, nil)

  def token, do: get(:token)
  def application_id, do: get(:application_id)
  def bot_module, do: get(:bot_module)
end
