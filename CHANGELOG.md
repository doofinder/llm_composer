# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.12.0] - 2025-10-17

### Removed
- Removed support for deprecated `:provider` and `:provider_opts` settings keys. Use `:providers` list instead.
- Removed support for global `:api_key` setting in Settings struct. Specify `:api_key` per-provider in the `:providers` list.
- Removed backward compatibility handling for deprecated settings in `LlmComposer` and `ProvidersRunner`.

### Added
- Automatic cost tracking for OpenAI, Google, and OpenRouter providers:
  - Fetches real-time pricing from provider APIs (models.dev for OpenAI/Google, OpenRouter API).
  - `CostInfo` struct in responses with token usage and cost breakdowns.
  - Support for automatic and manual pricing configuration.
- `Pricing` module for cost calculations.
- Supporting modules for OpenRouter pricing and tracking.

### Changed
- Enhanced `LlmResponse` to include cost information.
- Updated provider implementations (OpenAI, Google, OpenRouter) to support cost tracking.
- Updated README with examples for cost tracking.
- Refactored cost information retrieval and pricing module structure for improved maintainability.
- Updated AGENTS.md with current development guidelines.

## [0.11.2] - 2025-09-25

- Updated README a bit more docs and examples. Included in new release for hex docs too.

## [0.11.1] - 2025-09-23

- Added OpenRouter function-call support and provider message-mapping fixes; preserved assistant tool_calls during auto-executed functions.

## [0.11.0] - 2025-09-23

- **Implement multi-provider support with provider routing and failover:**
  - Introduced a new `:providers` list in `LlmComposer.Settings` to replace deprecated `:provider` and `:provider_opts` keys.
  - Added validation in `LlmComposer` to enforce/suggest exclusive use of `:providers` and warn about deprecated keys.
  - Implemented `LlmComposer.ProvidersRunner` to handle provider execution, supporting multiple providers with fallback logic.
  - Added `LlmComposer.ProviderRouter` behaviour for routing strategies on provider selection, failure handling, and blocking.
  - Provided a simple default provider router `LlmComposer.ProviderRouter.Simple` with exponential backoff blocking on provider failures.
  - Refactored `LlmComposer.run_completion/3` to delegate to `ProvidersRunner` for provider selection and execution.
- Optimized `LlmComposer.Cache.Ets` by switching `put` and `delete` calls to asynchronous casts, improving performance.
- Maintained backward compatibility with deprecated settings keys, issuing warnings and supporting legacy calls until version 0.12.0.
- Changed `response_format` key to `response_schema` for better structured output definition that works across multiple providers.
  - Structured outputs now available for OpenAI provider as well.
  - Default JSON module is JSON; falls back to Jason if JSON is not loaded.

## [0.10.0] - 2025-09-03
- **Add Google (Gemini) provider**: Full feature support including chat, functions, streaming, and structured outputs.
- **Add Vertex AI integration**: Same Google provider but can be used with it's Vertex API. Enterprise support with OAuth 2.0 authentication via Goth library.

## [0.9.0] - 2025-09-01
- Update elixir(1.18) and erlang(28).

## [0.8.0] - 2025-08-12
- **Add tracking costs for OpenRouter provider**: Introduced cost tracking functionality specifically for the OpenRouter provider to monitor API usage expenses.

## [0.7.0] - 2025-07-31
- **Add HttpClient module**: Introduced a new HttpClient module for improved HTTP handling.
- **Add streaming read capability**: Added the capability of streaming read for LLM providers completions.
- **Documentation and config updates**: Updates to README.md and configuration files.

## [0.6.0] - 2025-07-17
- **Refactor Models to Providers**: Renamed the "Models" module to "Providers" to better reflect the architecture and improve code organization.
- **Fix optional ex_aws dependency**: Fixed the ex_aws dependency to be truly optional by adding missing `Code.ensure_loaded` checks that were making the dependency mandatory.

## [0.5.5] - 2025-07-08
- **Fix typos**: Fixed various typos throughout the codebase.

## [0.5.4] - 2025-07-07
- **Add support for structured outputs in OpenRouter**: Added functionality to support structured outputs when using the OpenRouter model.

## [0.5.3] - 2025-06-30
- **Remove provider_routing from OpenRouter**: Removed the `provider_routing` functionality from the OpenRouter model, simplifying the model configuration and request building process.

## [0.5.2] - 2025-06-19
- **Making `ex_aws` dependency optional**: `ex_aws` is only required for the Bedrock provider. Making it optional so it is not included in case Bedrock is not used. Additionally, removing the `Logger.error()` in case of a model error, delegating this to the caller of the library.

## [0.5.1] - 2025-06-12
- **Adjust `Message.content` specs**: For Bedrock, the `content` field of the message has to be a list, allowing for messages with with multi-type content (image + text).

## [0.5.0] - 2025-06-12
- **Include Bedrock Support**: Included Bedrock support as provider only with `completion()`s support.

## [0.3.5] - 2024-12-18
- **Fix default api_key setting value**: The default value was en empty string. Now it is nil to be evaluated as false when getting the key from the map later. 

## [0.3.4] - 2024-12-17
- **OpenAI API Keys**: Use an API key passed as a parameter when calling chat_completion — overriding the global API key defined in the config. The param is sent inside the settings. 

## [0.3.3] - 2024-12-04
- **Timeouts**: Configurable OpenAI's timeout. Default set to 50 seconds.

## [0.3.2] - 2024-12-03
- **Timeouts**: Fix OpenAI-timeout handling and increase Tesla's timeout to 5 seconds.

## [0.3.1] - 2024-10-14

### Added
- **Error Handling**: Introduced a new module `LlmComposer.Errors` with a custom `MissingKeyError` for better error management.
- **Removed Legacy Code**: Removed the `get_messages/4` function from `LlmComposer` to streamline message handling.

## [0.3.0] - 2024-10-10

### Added
- **System Prompt Handling**: Added support for an optional system prompt in `run_completion/3`. The `system_prompt` is now treated as `nil` when not provided.
- **Custom Message Flow Example**: Updated the `README.md` with an example of how to use the `run_completion/3` function directly with a custom message history.
- **Nil Message Handling in Models**: Handling the `nil` case when system_prompt not provided

## [0.2.0] - 2024-10-10

### Added
- Initial release with support for basic message handling, interaction with OpenAI and Ollama models, and a foundational structure for model settings and function execution.

---
[Unreleased]: https://github.com/doofinder/llm_composer/compare/0.12.0...HEAD
[0.12.0]: https://github.com/doofinder/llm_composer/compare/0.11.2...0.12.0
[0.11.2]: https://github.com/doofinder/llm_composer/compare/0.11.1...0.11.2
[0.11.1]: https://github.com/doofinder/llm_composer/compare/0.11.0...0.11.1
[0.11.0]: https://github.com/doofinder/llm_composer/compare/0.10.0...0.11.0
[0.10.0]: https://github.com/doofinder/llm_composer/compare/0.9.0...0.10.0
[0.9.0]: https://github.com/doofinder/llm_composer/compare/0.8.0...0.9.0
[0.8.0]: https://github.com/doofinder/llm_composer/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/doofinder/llm_composer/compare/0.6.0...0.7.0
[0.6.0]: https://github.com/doofinder/llm_composer/compare/0.5.5...0.6.0
[0.5.5]: https://github.com/doofinder/llm_composer/compare/0.5.4...0.5.5
[0.5.4]: https://github.com/doofinder/llm_composer/compare/0.5.3...0.5.4
[0.5.3]: https://github.com/doofinder/llm_composer/compare/0.5.2...0.5.3
[0.5.2]: https://github.com/doofinder/llm_composer/compare/0.5.1...0.5.2
[0.5.1]: https://github.com/doofinder/llm_composer/compare/0.5.0...0.5.1
[0.3.5]: https://github.com/doofinder/llm_composer/compare/0.3.4...0.3.5
[0.5.0]: https://github.com/doofinder/llm_composer/compare/0.3.5...0.5.0
[0.3.4]: https://github.com/doofinder/llm_composer/compare/0.3.3...0.3.4
[0.3.3]: https://github.com/doofinder/llm_composer/compare/0.3.2...0.3.3
[0.3.2]: https://github.com/doofinder/llm_composer/compare/0.3.1...0.3.2
[0.3.1]: https://github.com/doofinder/llm_composer/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/doofinder/llm_composer/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/doofinder/llm_composer/compare/d9f96d55859300d779d9c3899b4c33578bb2e362...0.2.0
[first commit]: https://github.com/doofinder/llm_composer/commit/d9f96d55859300d779d9c3899b4c33578bb2e362
