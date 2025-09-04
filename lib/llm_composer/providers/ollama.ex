defmodule LlmComposer.Providers.Ollama do
  @moduledoc """
  Provider implementation for Ollama

  Basically it calls the Ollama server api for getting the chat responses.
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.HttpClient
  alias LlmComposer.LlmResponse
  alias LlmComposer.Providers.Utils

  @impl LlmComposer.Provider
  def name, do: :ollama

  @impl LlmComposer.Provider
  @doc """
  Reference: https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-chat-completion
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)
    base_url = Utils.get_config(:ollama, :url, opts, "http://localhost:11434")
    client = HttpClient.client(base_url, opts)
    req_opts = Utils.get_req_opts(opts)

    if model do
      messages
      |> build_request(system_message, model, opts)
      |> then(&Tesla.post(client, "/api/chat", &1, opts: req_opts))
      |> handle_response()
      |> LlmResponse.new(name())
    else
      {:error, :model_not_provided}
    end
  end

  defp build_request(messages, system_message, model, opts) do
    base_request = %{
      model: model,
      stream: Keyword.get(opts, :stream_response, false),
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

  defp handle_response({:error, _} = resp), do: resp
end
