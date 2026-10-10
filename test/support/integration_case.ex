defmodule Lingo.IntegrationCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  @bot Lingo.IntegrationBot

  using do
    quote do
      @moduletag :integration
    end
  end

  setup_all do
    token = System.get_env("BOT_TOKEN")
    client_id = System.get_env("CLIENT_ID")

    if is_nil(token) or token == "" do
      raise "BOT_TOKEN not set in the environment"
    end

    # REST only: the config and a rate limiter, no gateway
    start_supervised!({Lingo.Instance, name: @bot, token: token, application_id: client_id})
    start_supervised!({Lingo.Rest.RateLimiter, bot: @bot})

    start_supervised!(
      {Task.Supervisor, name: Lingo.Instance.process_name(@bot, Lingo.TaskSupervisor)}
    )

    # setup_all callbacks in the using module run in this process too
    Lingo.put_bot(@bot)

    %{bot: @bot, token: token, client_id: client_id}
  end

  setup %{bot: bot} do
    Lingo.put_bot(bot)
    :ok
  end
end
