defmodule CanonicalTailwind.MixProject do
  use Mix.Project

  @version "0.1.5"
  @source_url "https://github.com/aptinio/canonical_tailwind"

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def project do
    [
      app: :canonical_tailwind,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [summary: [threshold: 84]],
      package: package(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:tailwind, "~> 0.3", optional: true},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:def_layout, "~> 0.1.0", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.13", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "deps.unlock --unused",
        "hex.audit",
        "format",
        "compile --warnings-as-errors",
        "credo --format oneline",
        "test --cover"
      ]
    ]
  end

  defp package do
    [
      description: "Canonicalizes Tailwind CSS utility classes in HEEx templates",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "https://hexdocs.pm/canonical_tailwind/changelog.html"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
