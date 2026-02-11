import Config

# Tesla Configuration
# Uncomment to use Finch (recommended for streaming and production)
# config :llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyFinch}

# Provider Configurations
# Configure API keys via environment variables or uncomment and set values
config :llm_composer,
  open_ai: [
    # api_key: System.get_env("OPENAI_API_KEY")
  ],
  google: [
    # api_key: System.get_env("GOOGLE_API_KEY")
  ],
  open_router: [
    # api_key: System.get_env("OPENROUTER_API_KEY")
  ],
  ollama: [
    url: "http://localhost:11434"
  ],
  bedrock: [
    # Configure via ex_aws
  ],
  cache_ttl: 60 * 60 * 24,
  timeout: 50_000,
  skip_retries: false,
  retry_opts: [
    max_retries: 3,
    delay: 1_000,
    max_delay: 10_000
  ],
  provider_router: [
    min_backoff_ms: 1_000,
    max_backoff_ms: :timer.minutes(5),
    cache_mod: LlmComposer.Cache.Ets,
    cache_opts: [
      name: LlmComposer.ProviderRouter.Simple,
      table_name: :llm_composer_provider_blocks
    ],
    name: LlmComposer.ProviderRouter.Simple
  ]

import_config "#{Mix.env()}.exs"
