defmodule LlmComposer.Tool do
  @moduledoc """
  Lightweight DSL for defining LLM tools via a module attribute.

  Annotate any public function with `@tool` and the macro will build the
  corresponding `LlmComposer.Function` struct at compile time — including a
  JSON Schema derived from the `args` keyword list — with no boilerplate.

  ## Usage

      defmodule MyApp.Tools do
        use LlmComposer.Tool

        @tool description: "Evaluates a math expression",
              args: [expression: [type: :string, required: true, doc: "e.g. \\"2 + 3 * 4\\""]]
        def calculator(%{"expression" => expr}) do
          {result, _} = Code.eval_string(expr)
          result
        end
      end

  Then pass the tools to a provider or the agent:

      functions = LlmComposer.Tool.functions(MyApp.Tools)

      settings = %LlmComposer.Settings{
        providers: [
          {LlmComposer.Providers.OpenAI,
           [model: "gpt-4.1-mini", functions: functions]}
        ],
        ...
      }

  ## `@tool` options

  - `:description` (required) — sent to the model to explain the tool
  - `:args` — keyword list of `{arg_name, arg_opts}`, where `arg_opts` supports:
    - `:type` — one of `:string`, `:integer`, `:number`, `:boolean`, `:array`,
      `:object`; defaults to `:string`
    - `:required` — whether the LLM must supply this argument; defaults to `false`
    - `:doc` — description of the argument included in the schema

  ## Tool function signature

  Each annotated function must accept a single `map()` argument with string keys
  (as returned by JSON decoding):

      def my_tool(%{"param" => value}) do
        ...
      end
  """

  alias LlmComposer.Function

  @typedoc "Options accepted by the `:args` list entries."
  @type arg_opts :: [
          type: :string | :integer | :number | :boolean | :array | :object,
          required: boolean(),
          doc: String.t()
        ]

  @typedoc "Options for the `@tool` module attribute."
  @type tool_opts :: [
          description: String.t(),
          args: [{atom(), arg_opts()}]
        ]

  defmacro __using__(_opts) do
    quote do
      @on_definition LlmComposer.Tool
      @before_compile LlmComposer.Tool
      Module.register_attribute(__MODULE__, :tool, accumulate: false)
      Module.register_attribute(__MODULE__, :__llm_tool_defs__, accumulate: true)
    end
  end

  @doc false
  @spec __on_definition__(Macro.Env.t(), :def | :defp, atom(), list(), list(), term()) :: :ok
  def __on_definition__(env, :def, name, _args, _guards, _body) do
    case Module.get_attribute(env.module, :tool) do
      nil ->
        :ok

      opts ->
        Module.put_attribute(env.module, :__llm_tool_defs__, {name, opts})
        Module.delete_attribute(env.module, :tool)
    end
  end

  def __on_definition__(_env, _kind, _name, _args, _guards, _body), do: :ok

  @doc false
  defmacro __before_compile__(env) do
    defs =
      env.module
      |> Module.get_attribute(:__llm_tool_defs__)
      |> Enum.reverse()

    module = env.module

    tool_structs =
      Enum.map(defs, fn {name, opts} ->
        %Function{
          mf: {module, name},
          name: to_string(name),
          description: Keyword.fetch!(opts, :description),
          schema: build_schema(Keyword.get(opts, :args, []))
        }
      end)

    quote do
      @doc false
      def __llm_tools__, do: unquote(Macro.escape(tool_structs))
    end
  end

  @doc """
  Returns all `LlmComposer.Function` structs defined with `@tool` in `module`.
  """
  @spec functions(module()) :: [Function.t()]
  def functions(module) when is_atom(module), do: module.__llm_tools__()

  @spec build_schema([{atom(), arg_opts()}]) :: map()
  defp build_schema(args) do
    properties =
      Map.new(args, fn {name, opts} ->
        prop = %{"type" => json_type(Keyword.get(opts, :type, :string))}

        prop =
          case Keyword.get(opts, :doc) do
            nil -> prop
            doc -> Map.put(prop, "description", doc)
          end

        {to_string(name), prop}
      end)

    required =
      args
      |> Enum.filter(fn {_name, opts} -> Keyword.get(opts, :required, false) end)
      |> Enum.map(fn {name, _opts} -> to_string(name) end)

    schema = %{"type" => "object", "properties" => properties}
    if required == [], do: schema, else: Map.put(schema, "required", required)
  end

  @spec json_type(atom()) :: String.t()
  defp json_type(:string), do: "string"
  defp json_type(:integer), do: "integer"
  defp json_type(:number), do: "number"
  defp json_type(:float), do: "number"
  defp json_type(:boolean), do: "boolean"
  defp json_type(:array), do: "array"
  defp json_type(:object), do: "object"
  defp json_type(other), do: to_string(other)
end
