# Function Calls

LlmComposer supports **manual function call execution** via the `LlmComposer.FunctionExecutor`
module. This gives you full control over when and how function calls are executed, without
automatic execution — useful when you need to:

- Log or audit function calls before execution
- Apply custom validation or filtering
- Execute calls in parallel with custom error handling
- Integrate with external systems before or after execution

Supported providers: **OpenAI**, **OpenRouter**, **Google**.

## The 3-Step Workflow

```elixir
Application.put_env(:llm_composer, :open_ai, api_key: "<your api key>")

defmodule ManualFunctionCallExample do
  alias LlmComposer.FunctionExecutor
  alias LlmComposer.Function
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  # Step 0: define the local function
  @spec calculator(map()) :: number() | {:error, String.t()}
  def calculator(%{"expression" => expr}) do
    if Regex.match?(~r/^[0-9\.\s\+\-\*\/\(\)]+$/, expr) do
      {result, _} = Code.eval_string(expr)
      result
    else
      {:error, "invalid expression"}
    end
  end

  defp calculator_function do
    %Function{
      mf: {__MODULE__, :calculator},
      name: "calculator",
      description: "Evaluate arithmetic expressions",
      schema: %{
        "type" => "object",
        "properties" => %{"expression" => %{"type" => "string"}},
        "required" => ["expression"]
      }
    }
  end

  def run() do
    functions = [calculator_function()]

    settings = %LlmComposer.Settings{
      providers: [
        {LlmComposer.Providers.OpenAI, [model: "gpt-4o-mini", functions: functions]}
      ],
      system_prompt: "You are a helpful math assistant."
    }

    user_prompt = "What is 15 + 27?"

    # Step 1: send the initial request — model may request function calls
    {:ok, resp} = LlmComposer.simple_chat(settings, user_prompt)

    case LlmResponse.function_calls(resp) do
      nil ->
        # model answered directly
        IO.puts("Assistant: #{resp.main_response.content}")

      function_calls ->
        # Step 2: execute each returned function call locally
        executed_calls =
          Enum.map(function_calls, fn call ->
            case FunctionExecutor.execute(call, functions) do
              {:ok, executed} -> executed
              {:error, _} -> call
            end
          end)

        tool_messages =
          LlmComposer.FunctionCallHelpers.build_tool_result_messages(executed_calls)

        user_message = %Message{type: :user, content: user_prompt}

        assistant_with_tools =
          LlmComposer.FunctionCallHelpers.build_assistant_with_tools(
            LlmComposer.Providers.OpenAI,
            resp,
            user_message,
            [model: "gpt-4o-mini", functions: functions]
          )

        # Step 3: send user + assistant(with tool calls) + tool results back
        messages = [user_message, assistant_with_tools] ++ tool_messages

        {:ok, final} = LlmComposer.run_completion(settings, messages)
        IO.puts("Assistant: #{final.main_response.content}")
    end
  end
end

ManualFunctionCallExample.run()
```

**What this demonstrates:**

- How to define a local function and a corresponding `LlmComposer.Function` descriptor.
- How `simple_chat/2` returns potential function call requests from the model.
- How to execute `FunctionCall` structs with `FunctionExecutor.execute/2`.
- How to build `:tool_result` messages with `FunctionCallHelpers.build_tool_result_messages/1`.
- How to construct the assistant message using `FunctionCallHelpers.build_assistant_with_tools/4`.
- How to submit results back with `run_completion/2` to get the final answer.

## FunctionExecutor.execute/2

```elixir
FunctionExecutor.execute(function_call, function_definitions)
```

**Parameters:**

- `function_call` — the `FunctionCall` struct returned by the model
- `function_definitions` — list of `Function` structs defining callable functions

**Returns:**

| Result | Description |
|---|---|
| `{:ok, executed_call}` | `FunctionCall` with `:result` populated |
| `{:error, :function_not_found}` | Function name not in definitions |
| `{:error, {:invalid_arguments, reason}}` | Failed to parse JSON arguments |
| `{:error, {:execution_failed, reason}}` | Exception during execution |
