# Agent Development Guide

## Build/Test Commands
- **Run tests**: `mix test`
- **Run single test**: `mix test test/path_to_test.exs`
- **Format code**: `mix format`
- **Lint code**: `mix credo`
- **Type check**: `mix dialyzer`
- **Compile**: `mix compile`
- **Dependencies**: `mix deps.get`

## Code Style Guidelines
- **Line length**: Max 120 chars (Credo)
- **Module structure**: StrictModuleLayout (aliases → requires → imports → attributes → functions)
- **Naming**: snake_case functions/variables, PascalCase modules, predicates end with `?`
- **Aliases**: Use `alias`, order alphabetically
- **Documentation**: All public functions need `@doc` and `@spec`
- **Error handling**: Tagged tuples `{:ok, result}` / `{:error, reason}`
- **Imports**: Minimize, prefer explicit module calls
- **Private functions**: Use `@spec` and `defp`
- **Logging**: Use `Logger` with appropriate levels

## Testing
- Test files: `test/` directory with `_test.exs` suffix
- Framework: ExUnit