defmodule LlmComposer.Providers.OpenAI do
  @moduledoc """
  Provider implementation for OpenAI

  Basically it calls the OpenAI api for getting the chat responses.
  """
  @behaviour LlmComposer.Provider

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.HttpClient
  alias LlmComposer.LlmResponse
  alias LlmComposer.Providers.Utils

  @impl LlmComposer.Provider
  def name, do: :open_ai

  @impl LlmComposer.Provider
  @doc """
  Reference: https://platform.openai.com/docs/api-reference/chat/create
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)
    api_key = get_key(opts)
    base_url = Utils.get_config(:open_ai, :url, opts, "https://api.openai.com/v1")
    client = HttpClient.client(base_url, opts)

    headers = [
      {"Authorization", "Bearer " <> api_key}
    ]

    req_opts = Utils.get_req_opts(opts)

    if model do
      messages
      |> build_request(system_message, model, opts)
      |> then(&Tesla.post(client, "/chat/completions", &1, headers: headers, opts: req_opts))
      |> handle_response(opts)
      |> LlmResponse.new(name(), opts)
    else
      {:error, :model_not_provided}
    end
  end

  defp build_request(messages, system_message, model, opts) do
    tools =
      opts
      |> Keyword.get(:functions)
      |> Utils.get_tools(name())

    base_request = %{
      model: model,
      tools: tools,
      stream: Keyword.get(opts, :stream_response),
      messages: Utils.map_messages([system_message | messages])
    }

    req_params = Keyword.get(opts, :request_params, %{})

    base_request
    |> Map.merge(req_params)
    |> maybe_structured_output(opts)
    |> Utils.cleanup_body()
  end

  @spec handle_response(Tesla.Env.result(), keyword()) :: {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}, _opts)
       when status in [200] do
    {:ok, %{response: body}}
  end

  defp handle_response({:ok, resp}, _opts) do
    {:error, resp}
  end

  defp handle_response({:error, reason}, _opts) do
    {:error, reason}
  end

  defp get_key(opts) do
    case Utils.get_config(:open_ai, :api_key, opts) do
      nil -> raise MissingKeyError
      key -> key
    end
  end

  defp maybe_structured_output(base_request, opts) do
    response_schema = Keyword.get(opts, :response_schema)

    if is_map(response_schema) do
      Map.put_new(base_request, :response_format, %{
        "type" => "json_schema",
        "json_schema" => %{
          "name" => "response",
          "strict" => true,
          "schema" => response_schema
        }
      })
    else
      base_request
    end
  end
end
