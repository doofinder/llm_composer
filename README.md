# LlmComposer

**LlmComposer** is an Elixir library that simplifies the interaction with large language models (LLMs) such as OpenAI's GPT, providing a streamlined way to build and execute LLM-based applications or chatbots. It currently supports multiple model providers, including OpenAI and Ollama, with features like auto-execution of functions and customizable prompts to cater to different use cases.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `llm_composer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:llm_composer, "~> 0.2.0"}
  ]
end
```

## Usage

### Simple Bot Definition


To create a basic chatbot using LlmComposer, you need to define a module that uses the LlmComposer.Caller behavior. The example below demonstrates a simple configuration with OpenAI as the model provider:


```elixir
Application.put_env(:llm_composer, :openai_key, "<your api key>")

defmodule MyChat do

  @settings %LlmComposer.Settings{
    model: LlmComposer.Models.OpenAI,
    model_opts: [model: "gpt-4o-mini"],
    system_prompt: "You are a helpful assistant."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyChat.simple_chat("hi")

IO.inspect(res.main_response)
```

Example of execution:

```
mix run sample.ex

16:41:07.594 [debug] input_tokens=18, output_tokens=9
%LlmComposer.Message{
  type: :assistant,
  content: "Hello! How can I assist you today?"
}
```

This will trigger a conversation with the assistant based on the provided system prompt.


### Using Ollama Backend

LlmComposer also supports the Ollama backend, allowing interaction with models hosted on Ollama.

Make sure to start the Ollama server first.


```elixir
# Set the Ollama URI in the application environment if not already configured
# Application.put_env(:llm_composer, :ollama_uri, "http://localhost:11434")

defmodule MyChat do

  @settings %LlmComposer.Settings{
    model: LlmComposer.Models.Ollama,
    model_opts: [model: "llama3.1"],
    system_prompt: "You are a helpful assistant."
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end
end

{:ok, res} = MyChat.simple_chat("hi")

IO.inspect(res.main_response)
```

Example of execution:

```
mix run sample_ollama.ex

17:08:34.271 [debug] input_tokens=, output_tokens=
%LlmComposer.Message{
  type: :assistant,
  content: "How can I assist you today?",
  metadata: %{
    original: %{
      "content" => "How can I assist you today?",
      "role" => "assistant"
    }
  }
}
```

No function calls support in Ollama (for now)


### Bot with external function call

You can enhance the bot's capabilities by adding support for external function execution. This example demonstrates how to add a simple calculator that evaluates basic math expressions:


```elixir
Application.put_env(:llm_composer, :openai_key, "<your api key>")

defmodule MyChat do

  @settings %LlmComposer.Settings{
    model: LlmComposer.Models.OpenAI,
    model_opts: [model: "gpt-4o-mini"],
    system_prompt: "You are a helpful math assistant that assists with calculations.",
    auto_exec_functions: true,
    functions: [
      %LlmComposer.Function{
        mf: {__MODULE__, :calculator},
        name: "calculator",
        description: "A calculator that accepts math expressions as strings, e.g., '1 * (2 + 3) / 4', supporting the operators ['+', '-', '*', '/'].",
        schema: %{
          type: "object",
          properties: %{
            expression: %{
              type: "string",
              description: "A math expression to evaluate, using '+', '-', '*', '/'.",
              example: "1 * (2 + 3) / 4"
            }
          },
          required: ["expression"]
        }
      }
    ]
  }

  def simple_chat(msg) do
    LlmComposer.simple_chat(@settings, msg)
  end

  @spec calculator(map()) :: number() | {:error, String.t()}
  def calculator(%{"expression" => expression}) do
    # Basic validation pattern to prevent arbitrary code execution
    pattern = ~r/^[0-9\.\s\+\-\*\/\(\)]+$/

    if Regex.match?(pattern, expression) do
      try do
        {result, _binding} = Code.eval_string(expression)
        result
      rescue
        _ -> {:error, "Invalid expression"}
      end
    else
      {:error, "Invalid expression format"}
    end
  end
end

{:ok, res} = MyChat.simple_chat("hi, how much is 1 + 2?")

IO.inspect(res.main_response)
```

Example of execution:

```
mix run functions_sample.ex

16:38:28.338 [debug] input_tokens=111, output_tokens=17

16:38:28.935 [debug] input_tokens=136, output_tokens=9
%LlmComposer.Message{
  type: :assistant,
  content: "1 + 2 is 3."
}
```

In this example, the bot first calls OpenAI to understand the user's intent and determine that a function (the calculator) should be executed. The function is then executed locally, and the result is sent back to the user in a second API call.

### Additional Features
* Auto Function Execution: Automatically executes predefined functions, reducing manual intervention.
* System Prompts: Customize the assistant's behavior by modifying the system prompt (e.g., creating different personalities or roles for your bot).

---

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/llm_composer>.

