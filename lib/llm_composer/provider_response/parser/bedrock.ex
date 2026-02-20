defmodule LlmComposer.ProviderResponse.Parser.Bedrock do
  @moduledoc false

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @spec parse({:ok | :error, any()}, atom(), keyword()) ::
          {:ok, LlmResponse.t()} | {:error, term()}
  def parse({:error, resp}, _provider, _opts), do: {:error, resp}

  def parse({:ok, %{response: response} = provider_response}, :bedrock, _opts) do
    [%{"text" => message_content}] = response["output"]["message"]["content"]
    role = String.to_existing_atom(response["output"]["message"]["role"])

    {:ok,
     LlmResponse.new(%{
       provider: :bedrock,
       status: :ok,
       main_response:
         Message.new(role, message_content, %{original: response["output"]["message"]}),
       input_tokens: response["usage"]["inputTokens"],
       output_tokens: response["usage"]["outputTokens"],
       cost_info: Map.get(provider_response, :cost_info),
       raw: response
     })}
  end

  def parse(result, provider, _opts) do
    {:error,
     %{
       reason: :unhandled_response_format,
       provider: provider,
       response: result
     }}
  end
end
