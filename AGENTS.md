# Agent Development Guide

Important: ensure credo and compile works before finishing any code changes

**IMPORTANT**: NEVER use git write commands (commit, tag, push, git add, etc.) unless explicit request of the user. Normally only use git for reading repository history if needed.

## Build/Test Commands
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
│   ├── errors.ex
│   ├── function.ex
│   ├── function_call.ex
│   ├── helpers.ex
│   ├── http_client.ex
│   ├── llm_response.ex
│   ├── message.ex
│   ├── provider.ex
│   ├── provider_router
│   │   └── simple.ex
│   ├── provider_router.ex
│   ├── providers
│   │   ├── bedrock.ex
│   │   ├── google.ex
│   │   ├── ollama.ex
│   │   ├── open_ai.ex
│   │   ├── open_router.ex
│   │   └── utils.ex
│   ├── providers_runner.ex
│   └── settings.ex
└── llm_composer.ex
test
├── llm_composer
│   ├── cost
│   │   ├── cost_assembler_test.exs
│   │   ├── cost_info_test.exs
│   │   ├── pricing_test.exs
│   │   └── providers
│   │       ├── google_test.exs
│   │       ├── ollama_test.exs
│   │       ├── open_ai_test.exs
│   │       ├── open_router_test.exs
│   │       └── utils_test.exs
│   ├── function_calls_auto_execution_test.exs
│   ├── provider_router_simple_test.exs
│   └── providers
│       ├── google_test.exs
│       ├── ollama_test.exs
│       ├── open_ai_test.exs
│       ├── open_router_test.exs
│       └── utils_test.exs
├── llm_composer_test.exs
└── test_helper.exs
```

NOTE: for updating this section, run `tree lib test` and use that output

## Cursor and Copilot Rules
- No `.cursor/rules/` or `.cursorrules` directory found
- No `.github/copilot-instructions.md` file found

This guide ensures consistency and quality for agentic coding in this Elixir repository.
