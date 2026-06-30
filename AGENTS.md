# Agent Development Guide

Important: before finishing any code changes, run `mix precommit` to verify everything passes.

**IMPORTANT**: NEVER use git write commands (commit, tag, push, git add, etc.) unless explicit request of the user. Normally only use git for reading repository history if needed.

## Build/Test Commands
- **Precommit check** (compile + format + credo + tests): `mix precommit` — run this before finishing any changes
- **Run tests**: `mix test`
- **Run single test**: `mix test test/llm_composer_test.exs` or `mix test test/file.exs:line_number` for specific test
- **Run tests with coverage**: `mix test --cover`
- **Format code**: `mix format`
- **Lint code**: `mix credo --strict`
- **Compile**: `mix compile`
- **Dependencies**: `mix deps.get`

## Code Style Guidelines
- **Line length**: Max 120 chars (from Credo config)
- **Module structure**: StrictModuleLayout (aliases, requires, imports, attributes, functions)
- **Naming**: snake_case for functions/variables, PascalCase for modules, predicates end with `?`
- **Aliases**: Use `alias`, order alphabetically
- **Documentation**: All public functions need `@doc` and `@spec`
- **Error handling**: Use tagged tuples `{:ok, result}` / `{:error, reason}`
- **Imports**: Minimize, prefer explicit module calls
- **Private functions**: Use `@spec` and `defp`
- **Logging**: Use `Logger` with appropriate levels (debug, info, warn, error)
- **Testing**: ExUnit framework, test files in `test/` with `_test.exs` suffix


## Library Structure

The project follows a modular organization separating core functionality, providers, and supporting modules:

```
lib
├── llm_composer
│   ├── agent
│   │   ├── result.ex
│   │   └── stream_collector.ex
│   ├── agent.ex
│   ├── cache
│   │   ├── behaviour.ex
│   │   └── ets.ex
│   ├── cost
│   │   ├── cost_assembler.ex
│   │   ├── fetchers
│   │   │   ├── models_dev.ex
│   │   │   └── open_router.ex
│   │   └── pricing.ex
│   ├── cost_info.ex
│   ├── credo_checks
│   │   └── grouped_functions.ex
│   ├── errors.ex
│   ├── function_call.ex
│   ├── function_call_extractors.ex
│   ├── function_call_helpers.ex
│   ├── function.ex
│   ├── function_executor.ex
│   ├── helpers.ex
│   ├── http_client.ex
│   ├── llm_response.ex
│   ├── message.ex
│   ├── provider.ex
│   ├── provider_response
│   │   ├── bedrock.ex
│   │   ├── google.ex
│   │   ├── ollama.ex
│   │   ├── open_ai.ex
│   │   ├── open_ai_responses.ex
│   │   ├── open_router.ex
│   │   ├── parser
│   │   │   ├── bedrock.ex
│   │   │   ├── google.ex
│   │   │   ├── ollama.ex
│   │   │   └── open_ai.ex
│   │   └── struct.ex
│   ├── provider_response.ex
│   ├── provider_router
│   │   └── simple.ex
│   ├── provider_router.ex
│   ├── providers
│   │   ├── bedrock
│   │   │   ├── http_client.ex
│   │   │   └── stream_operation.ex
│   │   ├── bedrock.ex
│   │   ├── google.ex
│   │   ├── ollama.ex
│   │   ├── open_ai.ex
│   │   ├── open_ai_responses
│   │   │   └── reasoning.ex
│   │   ├── open_ai_responses.ex
│   │   ├── open_router.ex
│   │   └── utils.ex
│   ├── providers_runner.ex
│   ├── provider_stream_chunk
│   │   ├── bedrock.ex
│   │   ├── google.ex
│   │   ├── ollama.ex
│   │   ├── open_ai.ex
│   │   ├── open_ai_responses.ex
│   │   ├── open_router.ex
│   │   ├── parser
│   │   │   ├── bedrock.ex
│   │   │   ├── google.ex
│   │   │   ├── ollama.ex
│   │   │   ├── open_ai.ex
│   │   │   └── open_ai_responses.ex
│   │   └── struct.ex
│   ├── provider_stream_chunk.ex
│   ├── settings.ex
│   └── stream_chunk.ex
└── llm_composer.ex
test
├── llm_composer
│   ├── agent
│   │   └── stream_collector_test.exs
│   ├── agent_test.exs         # LlmComposer.Agent tool-calling loop tests
│   ├── cost/                  # cost_assembler, cost_info, pricing tests
│   ├── providers/             # per-provider tests (bedrock, google, ollama, open_ai, open_router, utils)
│   ├── http_client_test.exs
│   ├── provider_router_simple_test.exs
│   └── stream_chunk_test.exs
├── llm_composer_test.exs
└── test_helper.exs
```

NOTE: for updating this section, run `tree lib test` and use that output

## Cursor and Copilot Rules
- No `.cursor/rules/` or `.cursorrules` directory found
- No `.github/copilot-instructions.md` file found

This guide ensures consistency and quality for agentic coding in this Elixir repository.
