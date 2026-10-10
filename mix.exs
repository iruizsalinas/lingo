defmodule Lingo.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/iruizsalinas/lingo"

  def project do
    [
      app: :lingo,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "Lingo",
      description: "An Elixir library for interacting with the Discord API",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/lingo/"
      },
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "Lingo",
      source_ref: "v#{@version}",
      extras: ["README.md"],
      groups_for_modules: [
        Bots: [
          Lingo.Bot,
          Lingo.Bot.Commands,
          Lingo.Bot.Options,
          Lingo.Context,
          Lingo.Collector,
          Lingo.Error,
          Lingo.CheckError,
          Lingo.Testing
        ],
        "HTTP and OAuth2": [Lingo.Endpoint, Lingo.OAuth2],
        "REST API": [Lingo.Api, ~r/^Lingo\.Api\./],
        Cache: [Lingo.Cache, ~r/^Lingo\.Cache\./],
        Gateway: [Lingo.Gateway, Lingo.Gateway.SessionStore, Lingo.Gateway.SessionStore.File],
        Voice: [~r/^Lingo\.Voice/],
        "Message content": [
          Lingo.Component,
          Lingo.Component.Layout,
          Lingo.Component.Modal,
          Lingo.Embed
        ],
        Utilities: [
          ~r/^Lingo.Helper./,
          Lingo.CDN,
          Lingo.Format,
          Lingo.Permissions,
          Lingo.Snowflake,
          Lingo.Telemetry
        ],
        Types: [~r/^Lingo\.Type\./]
      ]
    ]
  end
end
