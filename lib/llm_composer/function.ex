defmodule LlmComposer.Function do
  @moduledoc """
  Defines a struct for representing a callable function within the context of a language model interaction.

  This struct is used to define functions that can be executed by the language model based on user prompts or model responses. Each function includes information about its module and function name (`mf`), a unique name for identification, a description of its purpose, and a schema that defines the expected input format.

  ## Fields

    - `mf`: A tuple `{module, function_name}` specifying the module and the function to be called. The function must accept the arguments defined in the `schema`.
    - `name`: A string that uniquely identifies the function within the language model's context.
    - `description`: A brief description of the function, outlining its purpose and expected usage.
    - `schema`: A map that defines the input schema of the function, detailing the expected parameters and their types. This helps the language model understand how to correctly format the input when calling the function.

  ## Example

  Here's how you might define a function struct for a simple calculator function and implement the corresponding module and function:

  ```elixir
  defmodule MyModule do
    def calculate(%{"expression" => expression}) do
      try do
        {result, _binding} = Code.eval_string(expression)
        result
      rescue
        _ -> {:error, "Invalid expression"}
      end
    end
  end

  # Define the function struct using the defined module and function
  %LlmComposer.Function{
    mf: {MyModule, :calculate},
    name: "calculator",
    description: "A simple calculator function that evaluates basic math expressions.",
    schema: %{
      type: "object",
      properties: %{
        expression: %{
          type: "string",
          description: "A mathematical expression to evaluate, e.g., '1 + 2'."
        }
      },
      required: ["expression"]
    }
  }
  ```
  """

  @type t() :: %__MODULE__{
          mf: {module(), atom()},
          name: String.t(),
          description: String.t(),
          schema: map()
        }

  @enforce_keys [:mf, :name, :description, :schema]
  defstruct mf: nil,
            name: nil,
            description: nil,
            schema: %{}
end
