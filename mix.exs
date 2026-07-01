defmodule LlmComposer.MixProject do
  use Mix.Project

  def project do
    [
      app: :llm_composer,
      version: "0.20.1",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: [
        main: "readme",
        source_ref: "master",
        extras: [
          "README.md",
          "guides/providers.md",
          "guides/agent.md",
          "guides/streaming.md",
          "guides/cost_tracking.md",
          "guides/function_calls.md",
          "guides/provider_router.md",
          "guides/custom_provider.md",
          "guides/configuration.md",
          "LICENSE"
        ],
        groups_for_extras: [
          Guides: ~r/guides\//
        ],
        groups_for_modules: [
          Core: [
            LlmComposer,
            LlmComposer.Provider,
            LlmComposer.Settings,
            LlmComposer.Message,
            LlmComposer.LlmResponse,
            LlmComposer.StreamChunk,
            LlmComposer.Function
          ],
          Agent: [
            LlmComposer.Agent,
            LlmComposer.Agent.Result
          ],
          Providers: ~r/LlmComposer\.Providers\./,
          "Response Parsing": ~r/LlmComposer\.ProviderResponse/,
          Streaming: ~r/LlmComposer\.ProviderStreamChunk/,
          "Function Calling": [
            LlmComposer.FunctionCall,
            LlmComposer.FunctionCallExtractors,
            LlmComposer.FunctionCallHelpers,
            LlmComposer.FunctionExecutor
          ],
          "Cost Tracking": ~r/LlmComposer\.Cost/,
          Routing: [
            LlmComposer.ProvidersRunner,
            LlmComposer.ProviderRouter,
            LlmComposer.ProviderRouter.Simple
          ],
          Cache: ~r/LlmComposer\.Cache/,
          Internals: [
            LlmComposer.Helpers,
            LlmComposer.Errors,
            LlmComposer.HttpClient
          ]
        ]
      ],
      source_url: "https://github.com/doofinder/llm_composer",
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:credo]],
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        precommit: :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    is_json_present? = Code.ensure_loaded?(JSON)

    [
      {:bypass, "~> 2.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:decimal, "~> 3.0 or ~> 2.3"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_aws, "~> 2.6", optional: true},
      {:hackney, "~> 1.21", optional: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false, warn_if_outdated: true},
      {:excoveralls, "~> 0.18", only: :test},
      {:finch, "~> 0.18", optional: true},
      {:goth, "~> 1.4", optional: true},
      {:jason, "~> 1.4", optional: is_json_present?},
      {:mint, "~> 1.7"},
      {:telemetry, "~> 1.0"},
      {:tesla, "~> 1.16"}
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test"
      ]
    ]
  end

  defp package() do
    [
      description:
        "LlmComposer is an Elixir library that facilitates chat interactions with language models, providing tools to handle user messages, generate responses, and execute functions automatically based on model outputs.",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/doofinder/llm_composer"}
    ]
  end
end
