# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added `:sse_middleware` option for streaming responses that allows loading custom middlewares.
- Added module `LlmComposer.Middleware.SSE`.
- Added `LlmComposer.Agent` — an agentic tool-calling loop on top of `LlmComposer.run_completion/3` that automates the full `ask → tool calls → execute → feed results back → repeat` cycle until the model returns a final, tool-free answer. Supports `:sequential` (default) and `:parallel` tool execution (`:tool_timeout`), a configurable `:max_iterations` (default `10`), and per-tool error recovery (tool failures are fed back to the model instead of aborting the run). Returns a `LlmComposer.Agent.Result` struct bundling the final response, the full conversation, executed tool calls, and accumulated cost info. Emits its own `[:llm_composer, :agent, :run | :iteration | :tool]` telemetry events.
- Added `:telemetry` spans for observability: `[:llm_composer, :run_completion]` (with `input_tokens`/`output_tokens` measurements and a `status` of `:ok`/`:error`) and `[:llm_composer, :providers_runner, :call]` (with `provider`, `model`, and `status` metadata). The provider call span is emitted for both the single-provider and the multi-provider (fallback) paths. The existing `%{latency_ms, status, provider, model}` metrics map passed to `LlmComposer.ProviderRouter` callbacks is preserved, so custom routers keep working unchanged.
- Added a custom `LlmComposer.CredoChecks.GroupedFunctions` Credo check that enforces grouping of all public functions before private ones within a module, and enabled it across the codebase.

### Fixed
- Fixed handling of incomplete or unterminated final SSE messages in streaming responses to avoid parse errors.

## [0.19.6] - 2026-06-16

### Changed
- Relaxed the declared `decimal` dependency constraint to support both 2.3.x and 3.x. `llm_composer`'s cost/pricing code was already compatible with Decimal 3.x, but downstream applications previously needed `override: true` to adopt the patched Decimal 3 line.

## [0.19.5] - 2026-06-01

### Added
- Bedrock HTTP receive timeout is now configurable via `config :llm_composer, :bedrock, receive_timeout: <ms>`. Falls back to the global `config :llm_composer, :timeout` and then to the previous hardcoded default of 30 000 ms. Applies to all Mint-based paths (streaming and non-streaming) as well as the shared `handle_stream_response` helpers used by Finch streaming.

## [0.19.4] - 2026-05-05

### Fixed
- Fixed Google cached token tracking: `cachedContentTokenCount` from `usageMetadata` is now extracted and populated in both `LlmResponse.cached_tokens` (non-streaming) and `StreamChunk.usage.cached_tokens` (streaming) instead of always being `nil`.

## [0.19.3] - 2026-04-30

### Fixed
- Fixed SSE streaming with `Tesla.Adapter.Mint`: the adapter now receives `body_as: :stream` instead of `response: :stream`, which is the correct option for Mint. Finch continues to use `response: :stream`. This means streaming no longer requires Finch — Mint (the default adapter) works out of the box.

## [0.19.2] - 2026-04-22

### Fixed
- Fixed reasoning (thinking) support to the Google stream chunk parser: chunks with `"thought": true` parts are now correctly split from text parts, populate the `StreamChunk.reasoning` field, and are emitted as `:reasoning_delta` instead of being mixed into `:text_delta`.

### Added
- Added `child_spec/1` to `LlmComposer.ProviderRouter.Simple` so it can be added to a supervision tree as a bare module (`children = [LlmComposer.ProviderRouter.Simple]`) without needing an explicit child spec map.
- Added HexDocs guides: Providers, Streaming, Cost Tracking, Function Calls, Provider Router, Custom Providers, Configuration Reference — splitting the previous monolithic README into focused, navigable documentation pages.
- Added `@doc` to `LlmComposer.Provider` behaviour callbacks and `@typedoc` to `Message`, `LlmResponse`, and `Settings` struct types for better in-editor and HexDocs documentation.

### Changed
- Slimmed `README.md` — it now serves as a discovery and getting-started document, with links to the full HexDocs guides for reference material.

## [0.19.1] - 2026-04-10

### Fixed
- Fixed Bedrock HTTP client non-streaming requests to use HTTP/1.1 (`protocols: [:http1]`) instead of HTTP/2 — Mint does not automatically manage HTTP/2 flow control (context window), which requires manual handling that is unnecessary for simple one-shot requests. Also corrected the `Mint.HTTP.request/5` error tuple to unwrap the connection from `{:error, _conn, error}` before returning.

## [0.19.0] - 2026-04-07

### Added
- Added automatic cost tracking for the Bedrock provider: token usage and costs are now populated in `LlmResponse.cost_info` when `track_costs: true` is set. Pricing is fetched automatically from models.dev (`amazon-bedrock` dataset) with a three-step lookup: exact model name, region prefix stripped (`eu.`, `us.`, `ap.`, `global.`), then date suffix stripped. Explicit `input_price_per_million` / `output_price_per_million` opts are also supported.
- Added streaming support for Amazon Bedrock via the `ConverseStream` API, with AWS Event Stream binary frame parsing.
- Added tool calls (function calling) support for Bedrock: request serialization with `toolConfig`, `toolUse` extraction from responses, `toolResult` formatting, and automatic merging of consecutive tool-result user turns as required by the Bedrock API.
- Added `LlmComposer.Providers.Bedrock.HttpClient` — a custom ExAws HTTP client that uses Mint by default for both streaming and regular requests, with optional Finch support when `config :llm_composer, :tesla_adapter, {Tesla.Adapter.Finch, name: MyFinch}` is set.
- Added `ProviderStreamChunk.Parser.Bedrock` to normalize Bedrock stream events (`text_delta`, `done`, `usage`) into the shared `StreamChunk` format.
- Added `response_schema` structured output support for Bedrock: pass a JSON schema map and it is automatically mapped to the Bedrock Converse API `outputConfig` format (schema is JSON-encoded as required by the API).

### Changed
- Bedrock now auto-injects `LlmComposer.Providers.Bedrock.HttpClient` as the ExAws HTTP client when `config :ex_aws, :http_client` is not explicitly set, removing the previous requirement to configure Hackney or Finch manually.

## [0.18.2] - 2026-04-01

### Changed
- Renamed `StreamChunk.tool_call` to `tool_calls` and updated its typespec from `map() | nil` to `list(LlmComposer.FunctionCall.t() | map()) | nil` — the field was already carrying a list in all parsers, so this aligns the struct definition with actual runtime values.

### Fixed
- Fixed Google streaming cost info to be built whenever usage data is present, not only on `:done` chunks — removes the unused `type` parameter from `build_cost_info/4`.

## [0.18.1] - 2026-04-01

### Added
- Added `:tool_call_delta` stream chunk type for Google provider: chunks containing `functionCall` parts are now correctly classified as `:tool_call_delta` with the `tool_call` field populated as a list of `%LlmComposer.FunctionCall{}` structs, instead of being silently emitted as empty `:text_delta` chunks.
- Added `reasoning_tokens` extraction from `thoughtsTokenCount` in Google streaming responses — the final `:done` chunk now populates `chunk.usage.reasoning_tokens` for Gemini thinking models.
- Added `reasoning_tokens` extraction from `thoughtsTokenCount` in Google non-streaming responses — `LlmResponse.reasoning_tokens` is now populated from `usageMetadata.thoughtsTokenCount`.

## [0.18.0] - 2026-03-26

### Added
- Added `function_calls` as a typed `[LlmComposer.FunctionCall.t()] | nil` field directly on `%LlmComposer.Message{}`, replacing the untyped `metadata[:tool_calls]` map access previously used in conversation history.
- Added `LlmResponse.function_calls/1` delegate function for convenient access to the function calls of the main response message.

### Changed
- Moved `function_calls` from `%LlmComposer.LlmResponse{}` struct field to `%LlmComposer.Message{}`, eliminating the duplication between `LlmResponse.function_calls` (initial response) and `Message.metadata[:tool_calls]` (conversation history). OpenAI, OpenRouter, and Google parsers now set `function_calls` directly on the assistant message.
- Updated `Providers.Utils` message mappers for OpenAI, OpenRouter, and Google to read `message.function_calls` instead of `message.metadata[:tool_calls]`.

## [0.17.1] - 2026-03-26

### Fixed
- Fixed Google provider parallel tool call message mapping to correctly merge consecutive `functionResponse` user turns into a single turn as required by the Google API.

## [0.17.0] - 2026-03-25

### Added
- Added `:reasoning_delta` stream chunk support for OpenAI, OpenAI Responses, and Ollama streams, including `reasoning` and `reasoning_details` payloads on normalized `%LlmComposer.StreamChunk{}` values.
- Added parsing of reasoning summary blocks from OpenAI Responses streaming events (`response.output_item.done` and `response.completed`).
- Added `reasoning_tokens`, `provider_model`, `cached_tokens`, and `response_id` fields to `%LlmComposer.LlmResponse{}` so consuming apps no longer need to dig into raw provider response structures.
- Added `cached_tokens` and `reasoning_tokens` to the `StreamChunk.usage()` type, populated on the final `:usage`/`:done` chunk for OpenAI, OpenAI Responses, OpenRouter, and Google streams.
- Added `cost_info` population on the final stream chunk (`:usage` or `:done`) for all providers — consumers can read `chunk.cost_info` directly instead of computing it after the stream.
- Added `cached_tokens` and `cache_read_price_per_million` fields to `%LlmComposer.CostInfo{}`.
- Added `cache_read_price_per_million` extraction from models.dev API responses when available, enabling automatic cache-read pricing for OpenAI models.
- Added `previous_response_id` forwarding in OpenAI Responses API requests via the `:previous_response_id` option.

### Fixed
- Fixed Google provider message mapping to preserve `thought_signature` and other fields from Gemini thinking models by reusing `parts` from the original response when available.

### Changed
- Updated OpenAI/OpenRouter response parsing to better handle streamed chunk lists, tuple-list payloads with string or atom keys, content arrays, and empty-choice errors.
- Updated Ollama response parsing so non-streaming responses map `message.thinking` into `reasoning`, and streaming responses preserve raw chunk lists for normalized stream parsing.
- Updated token and pricing extraction to support both map and keyword-style payloads when assembling cost information, using the actual response model for OpenAI/OpenAI Responses pricing.
- Updated pricing lookup so `:open_ai_responses` reuses OpenAI pricing data from models.dev, including fallback from dated snapshot model names to the base model entry.
- Updated cost calculation to bill cached prompt tokens with provider cache-read pricing when available, and fall back to standard input pricing when no separate cached-token price is exposed.
- Updated OpenAI Responses `normalize_usage` to preserve `input_tokens_details` so cached-token cost calculation receives the correct data downstream.
- Fixed compiler warnings introduced by Elixir 1.19: struct updates in `FunctionExecutor` and `LlmComposer` now include the required struct pattern match at the binding site.
- Moved `preferred_cli_env` from `def project` to the new `def cli` callback in `mix.exs`, removing the deprecation warning on Elixir 1.19+.
- Updated `credo` from 1.7.12 to 1.7.17 to fix a crash in `DuplicatedCode` check on Elixir 1.19.

## [0.16.2] - 2026-03-25

### Changed
- Adjusted `@spec` for `ProvidersRunner.run/3` to use `{:error, term()}` instead of `{:error, atom()}`, reflecting that errors are not always atoms.

## [0.16.1] - 2026-03-23

### Added
- Added `reasoning` and `reasoning_details` optional fields to `LlmComposer.Message` to capture reasoning tokens returned by reasoning models (e.g. via OpenRouter).
- OpenRouter provider now forwards `reasoning` and `reasoning_details` when serializing assistant messages, enabling multi-turn conversations that preserve reasoning context across requests.

### Changed
- Added `mix precommit` alias (compile + format check + credo + tests) for a single pre-commit verification command.

## [0.16.0] - 2026-02-23

### Added
- Added `LlmComposer.Providers.OpenAIResponses` provider to call OpenAI's `/responses` API, including support for `reasoning_effort` and structured outputs while keeping a normalized `LlmResponse` shape.
- Added `LlmComposer.StreamChunk` and provider-specific stream chunk parsing so streaming events are normalized into typed chunks (`:text_delta`, `:tool_call_delta`, `:done`, etc.).
- Added `LlmComposer.FunctionCallExtractors` to centralize provider-specific function call extraction logic.

### Changed
- Changed `LlmComposer.parse_stream_response` to be provider-aware (`parse_stream_response/2` and `parse_stream_response/3`) and return normalized `%LlmComposer.StreamChunk{}` values instead of raw decoded maps.
- Updated cost/token extraction to include `:open_ai_responses` provider responses.
- Updated OpenAI request handling to use shared timeout/request option helpers (including adapter `receive_timeout` support).
- Refactored provider response parsing into protocol-based adapters (`LlmComposer.ProviderResponse` and `LlmComposer.ProviderStreamChunk`) for clearer provider-specific normalization.
- Updated `README.md` with OpenAI Responses API and normalized streaming chunk documentation.
- Expanded `LlmComposer.Provider` moduledoc with a minimal implementation guide for creating custom providers.
- Updated ExDoc configuration to include `LICENSE` in docs extras.
- Updated dependency `ex_doc` from `0.31` to `0.34` and enabled `warn_if_outdated: true`.

## [0.15.0] - 2026-02-17

### Added
- Added configurable JSON engine for HTTP requests: new `:json_engine` config option allows specifying JSON encoder/decoder library (defaults to JSON, falls back to Jason).

### Changed
- Changed Google provider to keep `additionalProperties` in response schemas instead of removing them, allowing for more flexible schema definitions.
- Updated dependency `ex_aws` from 2.5 to 2.6.
- Updated dependency `tesla` from 1.14 to 1.16.
- Restructured configuration in `config/config.exs` with better provider organization.

## [0.14.2] - 2026-02-10

### Changed
- Changed `LlmResponse.new/3` to return an error tuple instead of raising an exception when encountering unhandled response formats from providers, for easier error handling/debugging.

## [0.14.1] - 2026-02-09

### Fixed
- Fixed `request_params` merging to use deep merge instead of shallow merge, allowing nested configurations (like `generationConfig` in Google provider) to be properly combined with provider defaults.

## [0.14.0] - 2026-02-04

### Added
- Configurable retry/backoff for provider requests: new settings allow configuring retry attempts and backoff behavior for provider calls (e.g. max attempts, base delay, backoff factor). This improves robustness when providers return transient errors.

## [0.13.1] - 2026-01-09

### Added
- Added ability to set custom HTTP request headers for OpenRouter provider.
- Updated README with documentation on configuring custom headers for OpenRouter.

## [0.13.0] - 2025-12-01

### Changed
- Replaced the previous auto function execution workflow with a manual process powered by `FunctionExecutor` and `FunctionCallHelpers`, and added README guidance for executing OpenAI/OpenRouter/Google function calls explicitly.

### Added
- `LlmComposer.FunctionExecutor` for explicit/manual execution of function calls returned by providers.
- `LlmComposer.FunctionCallHelpers` with helpers to build assistant messages and tool-result messages when handling function calls.

### Changed
- Replaced the previous auto function execution workflow with a manual process and updated the public APIs accordingly.
- `LlmComposer.LlmResponse` now exposes `function_calls` instead of the previous `actions` field and normalizes provider-specific function-call formats.
- `LlmComposer.Providers.Utils` message mapping and request/response formatting updated to support explicit `:tool_result` messages and provider-specific assistant formats (OpenAI/Google/OpenRouter).
- `LlmComposer.Helpers` was simplified/trimmed to remove automatic execution helpers in favor of the manual executor.
- `README.md` updated with a new "Function Calls" section demonstrating the manual workflow, API usage, and examples.

### Breaking Changes
- Removed the auto-execution helpers/tests and related documentation that assumed functions ran automatically.
- Settings struct keys `:auto_exec_functions` and `:functions` were removed; function descriptors are expected to be provided per-call or via provider options.
- Tests that relied on automatic function execution were removed (`test/llm_composer/function_calls_auto_execution_test.exs`).

## [0.12.3] - 2025-11-07

### Changed
- decimal dep mandatory

## [0.12.2] - 2025-11-06

### Changed
- Changed license from GPL-3.0 to MIT
- Updated documentation and improved code examples

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
[Unreleased]: https://github.com/doofinder/llm_composer/compare/0.19.6...HEAD
[0.19.6]: https://github.com/doofinder/llm_composer/compare/0.19.5...0.19.6
[0.19.5]: https://github.com/doofinder/llm_composer/compare/0.19.4...0.19.5
[0.19.4]: https://github.com/doofinder/llm_composer/compare/0.19.3...0.19.4
[0.19.3]: https://github.com/doofinder/llm_composer/compare/0.19.2...0.19.3
[0.19.2]: https://github.com/doofinder/llm_composer/compare/0.19.1...0.19.2
[0.19.1]: https://github.com/doofinder/llm_composer/compare/0.19.0...0.19.1
[0.19.0]: https://github.com/doofinder/llm_composer/compare/0.18.2...0.19.0
[0.18.2]: https://github.com/doofinder/llm_composer/compare/0.18.1...0.18.2
[0.18.1]: https://github.com/doofinder/llm_composer/compare/0.18.0...0.18.1
[0.18.0]: https://github.com/doofinder/llm_composer/compare/0.17.1...0.18.0
[0.17.1]: https://github.com/doofinder/llm_composer/compare/0.17.0...0.17.1
[0.17.0]: https://github.com/doofinder/llm_composer/compare/0.16.2...0.17.0
[0.16.2]: https://github.com/doofinder/llm_composer/compare/0.16.1...0.16.2
[0.16.1]: https://github.com/doofinder/llm_composer/compare/0.16.0...0.16.1
[0.16.0]: https://github.com/doofinder/llm_composer/compare/0.15.0...0.16.0
[0.15.0]: https://github.com/doofinder/llm_composer/compare/0.14.2...0.15.0
[0.14.2]: https://github.com/doofinder/llm_composer/compare/0.14.1...0.14.2
[0.14.1]: https://github.com/doofinder/llm_composer/compare/0.14.0...0.14.1
[0.14.0]: https://github.com/doofinder/llm_composer/compare/0.13.1...0.14.0
[0.13.1]: https://github.com/doofinder/llm_composer/compare/0.13.0...0.13.1
[0.13.0]: https://github.com/doofinder/llm_composer/compare/0.12.3...0.13.0
[0.12.3]: https://github.com/doofinder/llm_composer/compare/0.12.2...0.12.3
[0.12.2]: https://github.com/doofinder/llm_composer/compare/0.12.0...0.12.2
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
