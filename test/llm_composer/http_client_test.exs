defmodule LlmComposer.HttpClientTest do
  use ExUnit.Case, async: true

  alias LlmComposer.HttpClient

  describe "client/2 with retry configuration" do
    setup do
      Application.delete_env(:llm_composer, :retry)
      :ok
    end

    test "disables retries when enabled: false is set in config" do
      Application.put_env(:llm_composer, :retry, enabled: false)

      client = HttpClient.client("http://example.com")

      middlewares = client.pre

      retry_middleware =
        Enum.find(middlewares, fn
          {Tesla.Middleware.Retry, :call, _args} -> true
          _ -> false
        end)

      assert is_nil(retry_middleware)
    end

    test "uses custom retry values from config" do
      Application.put_env(:llm_composer, :retry,
        max_retries: 5,
        delay: 2000,
        max_delay: 30_000
      )

      client = HttpClient.client("http://example.com")

      middlewares = client.pre

      retry_middleware =
        Enum.find(middlewares, fn
          {Tesla.Middleware.Retry, :call, _args} -> true
          _ -> false
        end)

      assert {Tesla.Middleware.Retry, :call, [retry_opts]} = retry_middleware
      assert retry_opts[:max_retries] == 5
      assert retry_opts[:delay] == 2000
      assert retry_opts[:max_delay] == 30_000
    end
  end

  describe "client/2 with streaming" do
    setup do
      Application.delete_env(:llm_composer, :retry)
      :ok
    end

    test "does not add retry middleware when stream_response is true" do
      client = HttpClient.client("http://example.com", stream_response: true)

      middlewares = client.pre

      retry_middleware =
        Enum.find(middlewares, fn
          {Tesla.Middleware.Retry, :call, _args} -> true
          _ -> false
        end)

      assert is_nil(retry_middleware)
    end
  end
end
