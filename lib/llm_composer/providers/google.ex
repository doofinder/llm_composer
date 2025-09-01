defmodule LlmComposer.Providers.Google do
  @moduledoc """
  Provider implementation for Google

  Basically it calls the Google api for getting the chat responses.
  """
  @behaviour LlmComposer.Provider

  require Logger

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.HttpClient
  alias LlmComposer.LlmResponse
  alias LlmComposer.Providers.Utils

  @base_url Application.compile_env(
              :llm_composer,
              :google_url,
              "https://generativelanguage.googleapis.com/v1beta/models/"
            )

  @impl LlmComposer.Provider
  def name, do: :google

  @impl LlmComposer.Provider
  @doc """
  Reference: https://platform.openai.com/docs/api-reference/chat/create
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)
    api_key = Keyword.get(opts, :api_key) || get_key()
    client = HttpClient.client(@base_url, opts)

    headers = [
      {"X-GOOG-API-KEY", api_key}
    ]

    req_opts = Utils.get_req_opts(opts)

    # stream or generate?
    suffix =
      if Keyword.get(opts, :stream_response) do
        "streamGenerateContent?alt=sse"
      else
        "generateContent"
      end

    if model do
      messages
      |> build_request(system_message, opts)
      |> then(&Tesla.post(client, "/#{model}:#{suffix}", &1, headers: headers, opts: req_opts))
      |> handle_response()
      |> LlmResponse.new(name())
    else
      {:error, :model_not_provided}
    end
  end

  defp build_request(messages, system_message, opts) do
    tools =
      opts
      |> Keyword.get(:functions)
      |> Utils.get_tools()

    unless is_nil(tools) or tools == [] do
      Logger.warning("tools not supported for Google provider in llm_composer, ignoring it")
    end

    base_request = %{
      contents: Utils.map_messages(messages, :google)
    }

    base_request =
      if is_nil(system_message) do
        base_request
      else
        Map.put(base_request, :system_instruction, %{
          "parts" => [%{"text" => system_message.content}]
        })
      end

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
    case Application.get_env(:llm_composer, :google_key) do
      nil -> raise MissingKeyError
      key -> key
    end
  end
end
