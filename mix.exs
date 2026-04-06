defmodule Lingo.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/iruizsalinas/lingo"

  def project do
    [
      app: :lingo,
      version: @version,
      elixir: "~> 1.16",
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
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:gun, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://iruizsalinas.github.io/lingo/"
      },
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "Lingo",
      source_ref: "v#{@version}"
    ]
  end
end
