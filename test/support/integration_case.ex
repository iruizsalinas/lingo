defmodule Lingo.IntegrationCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :integration
    end
  end

  setup_all do
    token = System.get_env("BOT_TOKEN")
    client_id = System.get_env("CLIENT_ID")

    if is_nil(token) or token == "" do
      raise "BOT_TOKEN not set - add it to .env.local"
    end

    Lingo.Config.put(:token, token)
    Lingo.Config.put(:application_id, client_id)

    case Lingo.Api.RateLimiter.start_link([]) do
      {:ok, pid} ->
        %{rate_limiter: pid, token: token, client_id: client_id}

      {:error, {:already_started, pid}} ->
        %{rate_limiter: pid, token: token, client_id: client_id}
    end
  end
end
