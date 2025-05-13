defmodule LlmComposer.Models.OpenRouter do
  @moduledoc """
  Model implementation for OpenRouter

  OpenRouter API is very similar to Open AI API, but with some extras like model fallback.
  """
  @behaviour LlmComposer.Model

  use Tesla

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.LlmResponse
  alias LlmComposer.Models.Utils

  require Logger

  @default_timeout 50_000

  plug(
    Tesla.Middleware.BaseUrl,
    Application.get_env(:llm_composer, :open_router_url, "https://openrouter.ai/api/v1")
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

  @impl LlmComposer.Model
  def model_id, do: :open_router

  @impl LlmComposer.Model
  @doc """
  Reference: https://openrouter.ai/docs/api-reference/chat-completion
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
      |> handle_response(opts)
      |> LlmResponse.new(model_id())
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
    |> maybe_fallback_models(opts)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result(), keyword()) :: {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}, request_opts)
       when status in [200] do
    if Keyword.get(request_opts, :models) do
      original_model = Keyword.get(request_opts, :model)
      used_model = body["model"]

      if original_model != used_model do
        Logger.warning("The '#{used_model}' model has been used instead of '#{original_model}'")
      end
    end

    actions = Utils.extract_actions(body)
    {:ok, %{response: body, actions: actions}}
  end

  defp handle_response({:ok, resp}, _request_opts) do
    {:error, resp}
  end

  defp handle_response({:error, reason}, _request_opts) do
    {:error, reason}
  end

  defp get_key do
    case Application.get_env(:llm_composer, :open_router_key) do
      nil -> raise MissingKeyError
      key -> key
    end
  end

  defp maybe_fallback_models(base_request, opts) do
    fallback_models = Keyword.get(opts, :models)

    if fallback_models && is_list(fallback_models) do
      Map.put_new(base_request, :models, fallback_models)
    else
      base_request
    end
  end
end
