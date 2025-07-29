defmodule LlmComposer.Providers.OpenAI do
  @moduledoc """
  Model implementation for OpenAI

  Basically it calls the OpenAI api for getting the chat responses.
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.HttpClient
  alias LlmComposer.LlmResponse
  alias LlmComposer.Providers.Utils

  @base_url Application.compile_env(:llm_composer, :openai_url, "https://api.openai.com/v1")

  @impl LlmComposer.Provider
  def name, do: :open_ai

  @impl LlmComposer.Provider
  @doc """
  Reference: https://platform.openai.com/docs/api-reference/chat/create
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)
    api_key = Keyword.get(opts, :api_key) || get_key()
    client = HttpClient.client(@base_url, opts)

    headers = [
      {"Authorization", "Bearer " <> api_key}
    ]

    req_opts = Utils.get_req_opts(opts)

    if model do
      messages
      |> build_request(system_message, model, opts)
      |> then(&Tesla.post(client, "/chat/completions", &1, headers: headers, opts: req_opts))
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
      stream: Keyword.get(opts, :stream_response),
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
