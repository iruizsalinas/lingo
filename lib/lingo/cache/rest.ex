defmodule Lingo.Cache.Rest do
  @moduledoc false
  alias Lingo.Cache.{Access, Rest}

  def begin(method, path, opts) do
    resources = Lingo.Instance.get(:cache, %{})[:resources] || %{}
    # No route classification, snapshots, callbacks or payload traversal when off.
    if map_size(resources) == 0 do
      nil
    else
      plans =
        Enum.filter(Rest.Routes.plan(method, path, opts), fn {name, _, _} ->
          Map.has_key?(resources, name)
        end)

      if plans == [],
        do: nil,
        else: {plans, Access.call({:snapshot, Enum.uniq(Enum.map(plans, &elem(&1, 0)))})}
    end
  catch
    # Cache ownership can restart independently of an already running REST call.
    :exit, _ -> nil
  end

  def finish(nil, result), do: result
  def finish(_, {:error, _} = result), do: result

  def finish({plans, versions}, result) do
    data =
      case result do
        {:ok, data} -> data
        :ok -> nil
      end

    operations =
      Enum.reduce(plans, %{}, fn {name, mode, context}, acc ->
        actions = Rest.Response.actions(name, mode, context, data)
        Map.update(acc, name, actions, &(&1 ++ actions))
      end)

    Access.call({:rest, versions, operations})
    result
  rescue
    _ ->
      require Logger
      Logger.warning("REST cache update skipped because the response could not be cached")
      result
  catch
    :exit, _ -> result
  end
end
