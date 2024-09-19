defmodule LlmComposer.Models.Ollama do
  @moduledoc """
  Model implementation for Ollama

  Basically it calls the Ollama server api for getting the chat responses.
  """
  @behaviour LlmComposer.Model

  use Tesla

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

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

  @impl LlmComposer.Model
  def model_id, do: :ollama

  @impl LlmComposer.Model
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
      messages:
        map_messages([
          system_message | messages
        ])
    }

    req_params = Keyword.get(opts, :request_params, %{})

    base_request
    |> Map.merge(req_params)
    |> cleanup_body()
  end

  defp map_messages(messages) do
    Enum.map(messages, fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "content" => message}

      %Message{type: :system, content: message} ->
        %{"role" => "system", "content" => message}

      %Message{type: :assistant, content: message} ->
        %{"role" => "assistant", "content" => message}
    end)
  end

  @spec handle_response(Tesla.Env.result()) :: {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) when status in [200] do
    {:ok, %{response: body, actions: []}}
  end

  defp handle_response({:ok, resp}) do
    {:error, resp}
  end

  defp cleanup_body(body) do
    body
    |> Enum.reject(fn
      {_param, nil} -> true
      {_param, []} -> true
      _other -> false
    end)
    |> Map.new()
  end
end
