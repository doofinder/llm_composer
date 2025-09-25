defmodule LlmComposer.FunctionTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Function

  describe "struct creation" do
    test "creates a function with all required fields" do
      mf = {TestModule, :test_function}

      schema = %{
        type: "object",
        properties: %{
          param1: %{type: "string"}
        }
      }

      function = %Function{
        mf: mf,
        name: "test_function",
        description: "A test function",
        schema: schema
      }

      assert function.mf == mf
      assert function.name == "test_function"
      assert function.description == "A test function"
      assert function.schema == schema
    end

    test "fails to create function without required fields" do
      # Missing mf
      assert_raise ArgumentError, fn ->
        struct!(Function,
          name: "test",
          description: "desc",
          schema: %{}
        )
      end

      # Missing name
      assert_raise ArgumentError, fn ->
        struct!(Function,
          mf: {TestModule, :func},
          description: "desc",
          schema: %{}
        )
      end

      # Missing description
      assert_raise ArgumentError, fn ->
        struct!(Function,
          mf: {TestModule, :func},
          name: "test",
          schema: %{}
        )
      end

      # Missing schema
      assert_raise ArgumentError, fn ->
        struct!(Function,
          mf: {TestModule, :func},
          name: "test",
          description: "desc"
        )
      end
    end

    test "creates calculator function example from docs" do
      schema = %{
        type: "object",
        properties: %{
          expression: %{
            type: "string",
            description: "A mathematical expression to evaluate, e.g., '1 + 2'."
          }
        },
        required: ["expression"]
      }

      function = %Function{
        mf: {MyModule, :calculate},
        name: "calculator",
        description: "A simple calculator function that evaluates basic math expressions.",
        schema: schema
      }

      assert function.mf == {MyModule, :calculate}
      assert function.name == "calculator"

      assert function.description ==
               "A simple calculator function that evaluates basic math expressions."

      assert function.schema == schema
    end

    test "creates function with complex schema" do
      schema = %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "User name"},
          age: %{type: "integer", description: "User age", minimum: 0},
          email: %{type: "string", format: "email"}
        },
        required: ["name", "email"]
      }

      function = %Function{
        mf: {UserModule, :create_user},
        name: "create_user",
        description: "Creates a new user account",
        schema: schema
      }

      assert function.mf == {UserModule, :create_user}
      assert function.name == "create_user"
      assert function.schema == schema
    end
  end

  describe "type specifications" do
    test "accepts valid module/function tuple for mf" do
      function = %Function{
        mf: {String, :upcase},
        name: "upcase",
        description: "Converts string to uppercase",
        schema: %{type: "object", properties: %{text: %{type: "string"}}}
      }

      assert %Function{} = function
      assert function.mf == {String, :upcase}
    end

    test "accepts empty schema map" do
      function = %Function{
        mf: {TestModule, :empty_func},
        name: "empty",
        description: "Function with no parameters",
        schema: %{}
      }

      assert function.schema == %{}
    end
  end
end
