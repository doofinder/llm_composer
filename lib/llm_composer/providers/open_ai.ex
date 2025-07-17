defmodule LlmComposer.Providers.OpenAI do
  @moduledoc """
  Model implementation for OpenAI

  Basically it calls the OpenAI api for getting the chat responses.
  """
  @behaviour LlmComposer.Provider

  use Tesla

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.LlmResponse
  alias LlmComposer.Providers.Utils

  @default_timeout 50_000

  plug(
    Tesla.Middleware.BaseUrl,
    Application.get_env(:llm_composer, :openai_url, "https://api.openai.com/v1")
  )

  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Retry,
    delay: :timer.seconds(1),
    max_delay: :timer.seconds(10),
    max_retries: 10,
    should_retry: fn
      {:ok, %{status: status}} when status in [429, 500, 503] -> true
      {:error, :closed} -> true
      _other -> false
    end
  )

  plug(Tesla.Middleware.Timeout,
    timeout: Application.get_env(:llm_composer, :timeout) || @default_timeout
  )

  @impl LlmComposer.Provider
  def name, do: :open_ai

  @impl LlmComposer.Provider
  @doc """
  Reference: https://platform.openai.com/docs/api-reference/chat/create
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)
    api_key = Keyword.get(opts, :api_key) || get_key()

    headers = [
      {"Authorization", "Bearer " <> api_key}
    ]

    if model do
      messages
      |> build_request(system_message, model, opts)
      |> then(&post("/chat/completions", &1, headers: headers))
      |> handle_response()
      |> LlmResponse.new(name())
    else
      {:error, :model_not_provided}
    end
  end

  defp build_request(messages, system_message, model, opts) do
    tools =
      opts
      |> Keyword.get(:functions)
      |> Utils.get_tools()

    base_request = %{
      model: model,
      tools: tools,
      messages: Utils.map_messages([system_message | messages])
    }

    req_params = Keyword.get(opts, :request_params, %{})

    base_request
    |> Map.merge(req_params)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result()) :: {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) when status in [200] do
    actions = Utils.extract_actions(body)
    {:ok, %{response: body, actions: actions}}
  end

  defp handle_response({:ok, resp}) do
    {:error, resp}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp get_key do
    case Application.get_env(:llm_composer, :openai_key) do
      nil -> raise MissingKeyError
      key -> key
    end
  end
end
