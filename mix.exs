defmodule LlmComposer.MixProject do
  use Mix.Project

  def project do
    [
      app: :llm_composer,
      version: "0.4.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md"],
        source_ref: "master"
      ],
      source_url: "https://github.com/doofinder/llm_composer"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:jason, "~> 1.4"},
      {:tesla, "~> 1.12"}
    ]
  end

  defp package() do
    [
      description:
        "LlmComposer is an Elixir library that facilitates chat interactions with language models, providing tools to handle user messages, generate responses, and execute functions automatically based on model outputs.",
      licenses: ["GPL-3.0"],
      links: %{"GitHub" => "https://github.com/doofinder/llm_composer"}
    ]
  end
end
