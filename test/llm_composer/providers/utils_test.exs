defmodule LlmComposer.Providers.UtilsTest do
  use ExUnit.Case, async: true

  alias LlmComposer.Providers.Utils

  test "get_req_opts returns stream adapter when stream_response true" do
    assert Utils.get_req_opts(stream_response: true) == [adapter: [response: :stream]]
  end

  test "get_req_opts returns empty list when stream_response not set" do
    assert Utils.get_req_opts([]) == []
  end

  test "merge_request_params adds new keys" do
    base = %{model: "gpt-4", temperature: 0.7}
    req_params = %{max_tokens: 1000}

    result = Utils.merge_request_params(base, req_params)

    assert result == %{model: "gpt-4", temperature: 0.7, max_tokens: 1000}
  end

  test "merge_request_params overrides existing keys" do
    base = %{model: "gpt-4", temperature: 0.7}
    req_params = %{temperature: 0.9}

    result = Utils.merge_request_params(base, req_params)

    assert result == %{model: "gpt-4", temperature: 0.9}
  end

  test "merge_request_params deep merges generationConfig" do
    base = %{
      generationConfig: %{
        responseMimeType: "application/json",
        responseSchema: %{"type" => "object"}
      }
    }

    req_params = %{
      generationConfig: %{
        thinkingConfig: %{thinkingLevel: "low"},
        temperature: 0.8
      }
    }

    result = Utils.merge_request_params(base, req_params)

    assert result.generationConfig.responseMimeType == "application/json"
    assert result.generationConfig.responseSchema["type"] == "object"
    assert result.generationConfig.thinkingConfig.thinkingLevel == "low"
    assert result.generationConfig.temperature == 0.8
  end

  test "merge_request_params deep merges additionalConfig" do
    base = %{
      additionalConfig: %{
        key1: "value1"
      }
    }

    req_params = %{
      additionalConfig: %{
        key2: "value2"
      }
    }

    result = Utils.merge_request_params(base, req_params)

    assert result.additionalConfig.key1 == "value1"
    assert result.additionalConfig.key2 == "value2"
  end

  test "merge_request_params overrides nested values in generationConfig" do
    base = %{
      generationConfig: %{
        temperature: 0.7,
        topP: 0.9
      }
    }

    req_params = %{
      generationConfig: %{
        temperature: 0.2
      }
    }

    result = Utils.merge_request_params(base, req_params)

    assert result.generationConfig.temperature == 0.2
    assert result.generationConfig.topP == 0.9
  end

  test "merge_request_params handles empty req_params" do
    base = %{model: "gpt-4", temperature: 0.7}

    result = Utils.merge_request_params(base, %{})

    assert result == %{model: "gpt-4", temperature: 0.7}
  end

  test "merge_request_params merges response_schema generationConfig with request_params" do
    base = %{
      generationConfig: %{
        responseMimeType: "application/json",
        responseSchema: %{
          "type" => "object",
          "properties" => %{"answer" => %{"type" => "string"}}
        }
      }
    }

    req_params = %{
      generationConfig: %{
        maxOutputTokens: 8192
      }
    }

    result = Utils.merge_request_params(base, req_params)

    assert result.generationConfig.responseMimeType == "application/json"
    assert result.generationConfig.responseSchema["type"] == "object"
    assert result.generationConfig.responseSchema["properties"]["answer"]["type"] == "string"
    assert result.generationConfig.maxOutputTokens == 8192
  end
end
