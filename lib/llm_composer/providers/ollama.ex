defmodule LlmComposer.Providers.Ollama do
  @moduledoc """
  Model implementation for Ollama

  Basically it calls the Ollama server api for getting the chat responses.
  """
  @behaviour LlmComposer.Provider

  use Tesla

  alias LlmComposer.LlmResponse
  alias LlmComposer.Providers.Utils

  @uri Application.compile_env(:llm_composer, :ollama_uri, "http://localhost:11434")

  plug(Tesla.Middleware.BaseUrl, @uri)

  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Retry,
    delay: :timer.seconds(1),
    max_delay: :timer.seconds(10),
    max_retries: 5,
    should_retry: fn
      {:ok, %{status: status}} when status in [429, 500, 503] -> true
      {:error, :closed} -> true
      _other -> false
    end
  )

  @impl LlmComposer.Provider
  def model_id, do: :ollama

  @impl LlmComposer.Provider
  @doc """
  Reference: https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-chat-completion
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)

    if model do
      messages
      |> build_request(system_message, model, opts)
      |> then(&post("/api/chat", &1))
      |> handle_response()
      |> LlmResponse.new(model_id())
    else
      {:error, :model_not_provided}
    end
  end

  defp build_request(messages, system_message, model, opts) do
    base_request = %{
      model: model,
      stream: false,
      # tools: get_tools(Keyword.get(opts, :functions)),
      messages: Utils.map_messages([system_message | messages])
    }

    req_params = Keyword.get(opts, :request_params, %{})

    base_request
    |> Map.merge(req_params)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result()) :: {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) when status in [200] do
    {:ok, %{response: body, actions: []}}
  end

  defp handle_response({:ok, resp}) do
    {:error, resp}
  end
end
