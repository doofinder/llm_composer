defmodule LlmComposer.ToolTest do
  use ExUnit.Case, async: true

  defmodule MyTools do
    use LlmComposer.Tool

    @tool description: "Evaluates a math expression",
          args: [expression: [type: :string, required: true, doc: "e.g. \"2 + 3\""]]
    @spec calculator(map()) :: number()
    def calculator(%{"expression" => expr}) do
      {result, _} = Code.eval_string(expr)
      result
    end

    @tool description: "Greets a person",
          args: [
            name: [type: :string, required: true],
            formal: [type: :boolean]
          ]
    @spec greet(map()) :: String.t()
    def greet(%{"name" => name, "formal" => true}), do: "Good day, #{name}."
    def greet(%{"name" => name}), do: "Hey, #{name}!"

    @spec not_a_tool(map()) :: :ignored
    def not_a_tool(_), do: :ignored
  end

  setup do
    %{functions: LlmComposer.Tool.functions(MyTools)}
  end

  describe "functions/1" do
    test "returns only @tool-annotated functions", %{functions: functions} do
      names = Enum.map(functions, & &1.name)
      assert names == ["calculator", "greet"]
    end

    test "sets the correct mf tuple", %{functions: [calc | _]} do
      assert calc.mf == {MyTools, :calculator}
    end

    test "carries the description", %{functions: [calc | _]} do
      assert calc.description == "Evaluates a math expression"
    end
  end

  describe "JSON schema generation" do
    test "required arg appears in required list", %{functions: [calc | _]} do
      assert calc.schema["required"] == ["expression"]
    end

    test "optional arg is not in required list", %{functions: functions} do
      greet = Enum.find(functions, &(&1.name == "greet"))
      assert greet.schema["required"] == ["name"]
      refute "formal" in (greet.schema["required"] || [])
    end

    test "arg type maps to JSON Schema type string", %{functions: functions} do
      [calc | _] = functions
      assert calc.schema["properties"]["expression"]["type"] == "string"

      greet = Enum.find(functions, &(&1.name == "greet"))
      assert greet.schema["properties"]["formal"]["type"] == "boolean"
    end

    test "doc is included in property schema", %{functions: [calc | _]} do
      assert calc.schema["properties"]["expression"]["description"] == "e.g. \"2 + 3\""
    end

    test "arg without doc has no description key", %{functions: functions} do
      greet = Enum.find(functions, &(&1.name == "greet"))
      refute Map.has_key?(greet.schema["properties"]["name"], "description")
    end

    test "tool with no args produces empty properties and no required" do
      defmodule NoArgTools do
        use LlmComposer.Tool

        @tool description: "Pings the system"
        @spec ping(map()) :: :pong
        def ping(_), do: :pong
      end

      [ping] = LlmComposer.Tool.functions(NoArgTools)
      assert ping.schema == %{"type" => "object", "properties" => %{}}
    end
  end

  describe "annotated functions" do
    test "remain callable and return expected values", %{functions: [calc | _]} do
      {mod, fun} = calc.mf
      assert apply(mod, fun, [%{"expression" => "(2 + 3) * 4"}]) == 20
    end

    test "multi-clause functions are captured once", %{functions: functions} do
      greet = Enum.find(functions, &(&1.name == "greet"))
      assert greet != nil
      assert length(functions) == 2
    end
  end
end
