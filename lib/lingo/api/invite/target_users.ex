defmodule Lingo.Api.Invite.TargetUsers do
  @moduledoc false

  # Invite target users travel as a CSV file with a `user_id` header, up next
  # to the JSON payload when creating an invite; Discord processes it as a job.

  alias Lingo.Type.Parse

  @job_statuses %{0 => :unspecified, 1 => :processing, 2 => :completed, 3 => :failed}

  # the user ids in a CSV Discord sent, without its header
  def ids(csv) do
    csv
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.drop(1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # a list of user ids, a CSV string, or {filename, csv}
  def file(user_ids) when is_list(user_ids), do: file("user_id\n" <> Enum.join(user_ids, "\n"))

  def file({filename, csv}) when is_binary(filename),
    do: {"target_users_file", {csv, filename: filename, content_type: "text/csv"}}

  def file(csv) when is_binary(csv),
    do: {"target_users_file", {csv, filename: "target_users.csv", content_type: "text/csv"}}

  # an invite's request body: multipart when it carries a target users file
  def invite_body(params) do
    {file, params} = Map.pop(params, :target_users_file)
    {file, json} = if file, do: {file, params}, else: Map.pop(params, "target_users_file")

    if file do
      payload = {"payload_json", {JSON.encode!(json), content_type: "application/json"}}
      [multipart: [payload, file(file)]]
    else
      [json: json]
    end
  end

  def job(data) do
    %{
      status: Map.get(@job_statuses, data["status"], data["status"]),
      total_users: data["total_users"] || 0,
      processed_users: data["processed_users"] || 0,
      created_at: Parse.timestamp(data["created_at"]),
      completed_at: Parse.timestamp(data["completed_at"]),
      error_message: data["error_message"]
    }
  end
end
