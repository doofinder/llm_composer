if Code.ensure_loaded?(ExAws) do
  defmodule LlmComposer.Providers.Bedrock do
    @moduledoc """
    Provider implementation for Amazon Bedrock.

    Handles chat completion requests through Amazon Bedrock Converse API. Any
    Bedrock compatible model can be used. To specify any model-specific options for
    the request, you can pass them in the `request_params` option and they will
    be merged into the base request that is prepared.
    """
    @behaviour LlmComposer.Provider

    alias LlmComposer.Message
    alias LlmComposer.ProviderResponse
    alias LlmComposer.Providers.Utils

    @impl LlmComposer.Provider
    def name, do: :bedrock

    @impl LlmComposer.Provider
    @doc """
    Reference: https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html
    """
    def run(messages, system_message, opts) do
      model = Keyword.get(opts, :model)

      if model do
        messages
        |> build_request(system_message, opts)
        |> send_request(model)
        |> handle_response()
        |> wrap_response(opts)
      else
        {:error, :model_not_provided}
      end
    end

    @spec build_request(list(Message.t()), Message.t(), keyword()) :: map()
    defp build_request(messages, system_message, opts) do
      base_request = %{
        "messages" => Enum.map(messages, &format_message/1),
        "system" => [format_message(system_message)]
      }

      req_params = Keyword.get(opts, :request_params, %{})

      base_request
      |> Utils.merge_request_params(req_params)
      |> Utils.cleanup_body()
    end

    @spec send_request(map(), String.t()) :: {:ok, map()} | {:error, term()}
    defp send_request(payload, model) do
      operation = %ExAws.Operation.JSON{
        data: payload,
        headers: [{"Content-Type", "application/json"}],
        http_method: :post,
        path: "/model/#{model}/converse",
        service: :"bedrock-runtime"
      }

      config = [service_override: :bedrock]
      ExAws.request(operation, config)
    end

    @spec format_message(Message.t()) :: map()
    defp format_message(%Message{type: :system, content: content}) do
      %{"text" => content}
    end

    defp format_message(%Message{type: role, content: content}) when is_binary(content) do
      %{"role" => Atom.to_string(role), "content" => [%{"text" => content}]}
    end

    defp format_message(%Message{type: role, content: content}) do
      %{"role" => Atom.to_string(role), "content" => content}
    end

    @spec handle_response({:ok, map()} | {:error, map()}) :: {:ok, map()} | {:error, term}
    defp handle_response({:ok, %{"output" => %{"message" => _message}} = response}) do
      {:ok,
       %{
         response: response,
         input_tokens: get_in(response, ["usage", "inputTokens"]),
         output_tokens: get_in(response, ["usage", "outputTokens"])
       }}
    end

    defp handle_response({:error, resp}) do
      {:error, resp}
    end

    defp wrap_response(result, opts) do
      result
      |> ProviderResponse.Bedrock.new(opts)
      |> ProviderResponse.to_llm_response(opts)
    end
  end
end
