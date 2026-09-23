defmodule LlmComposer.ProviderResponse.Parser.GoogleTest do
  use ExUnit.Case, async: true

  alias LlmComposer.ProviderResponse.Parser.Google

  # Guarantees :assistant exists as an atom regardless of test run/load order,
  # since `parse/3` derives it from a string via `String.to_existing_atom/1`.
  setup_all do
    _ = :assistant
    :ok
  end

  describe "parse/3 with a normal candidate" do
    test "extracts the main response content" do
      response = %{
        "candidates" => [
          %{
            "content" => %{
              "role" => "model",
              "parts" => [%{"text" => "hello there"}]
            }
          }
        ],
        "usageMetadata" => %{"promptTokenCount" => 10, "candidatesTokenCount" => 5}
      }

      assert {:ok, llm_response} = Google.parse({:ok, %{response: response}}, :google, [])
      assert llm_response.main_response.content == "hello there"
      assert llm_response.main_response.type == :assistant
    end
  end

  describe "parse/3 when the response has no candidates" do
    test "returns a typed error instead of raising when candidates is missing (e.g. a safety block)" do
      response = %{
        "promptFeedback" => %{"blockReason" => "SAFETY"}
      }

      assert {:error, %{reason: :missing_candidates, provider: :google, response: ^response}} =
               Google.parse({:ok, %{response: response}}, :google, [])
    end

    test "returns a typed error instead of raising when candidates is an empty list" do
      response = %{"candidates" => []}

      assert {:error, %{reason: :missing_candidates, provider: :google, response: ^response}} =
               Google.parse({:ok, %{response: response}}, :google, [])
    end
  end
end
