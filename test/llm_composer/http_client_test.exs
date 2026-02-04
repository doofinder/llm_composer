defmodule LlmComposer.HttpClientTest do
  use ExUnit.Case

  alias LlmComposer.HttpClient

  describe "client/2 with retry configuration" do
    setup do
      prev = Application.get_env(:llm_composer, :skip_retries)

      on_exit(fn ->
        if prev == nil do
          Application.delete_env(:llm_composer, :skip_retries)
        else
          Application.put_env(:llm_composer, :skip_retries, prev)
        end
      end)

      Application.delete_env(:llm_composer, :skip_retries)
      :ok
    end

    test "disables retries when enabled: false is set in config" do
      Application.put_env(:llm_composer, :skip_retries, true)

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
      Application.put_env(:llm_composer, :retry_opts,
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

    test "uses custom should_retry function from opts" do
      custom_fn = fn
        {:ok, %{status: 502}} -> true
        _ -> false
      end

      client = HttpClient.client("http://example.com", retry_opts: [should_retry: custom_fn])

      middlewares = client.pre

      retry_middleware =
        Enum.find(middlewares, fn
          {Tesla.Middleware.Retry, :call, _args} -> true
          _ -> false
        end)

      assert {Tesla.Middleware.Retry, :call, [retry_opts]} = retry_middleware
      assert retry_opts[:should_retry] == custom_fn
    end

    test "uses custom should_retry function from config" do
      custom_fn = fn
        {:ok, %{status: 504}} -> true
        _ -> false
      end

      Application.put_env(:llm_composer, :retry_opts, should_retry: custom_fn)

      client = HttpClient.client("http://example.com")

      middlewares = client.pre

      retry_middleware =
        Enum.find(middlewares, fn
          {Tesla.Middleware.Retry, :call, _args} -> true
          _ -> false
        end)

      assert {Tesla.Middleware.Retry, :call, [retry_opts]} = retry_middleware
      assert retry_opts[:should_retry] == custom_fn
    end
  end

  describe "client/2 with streaming" do
    setup do
      Application.delete_env(:llm_composer, :skip_retries)
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
