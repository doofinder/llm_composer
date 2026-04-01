defmodule LlmComposer.ProviderResponse.Parser.Bedrock do
  @moduledoc false

  alias LlmComposer.FunctionCallExtractors
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @spec parse({:ok | :error, any()}, atom(), keyword()) ::
          {:ok, LlmResponse.t()} | {:error, term()}
  def parse({:error, resp}, _provider, _opts), do: {:error, resp}

  def parse({:ok, %{stream: stream}}, :bedrock, _opts) do
    {:ok,
     LlmResponse.new(%{
       provider: :bedrock,
       status: :ok,
       stream: stream,
       raw: stream
     })}
  end

  def parse({:ok, %{response: response} = provider_response}, :bedrock, _opts) do
    content = response["output"]["message"]["content"]
    role = String.to_existing_atom(response["output"]["message"]["role"])

    message_content = extract_text(content)
    function_calls = FunctionCallExtractors.from_bedrock_content(content)

    message = %{
      Message.new(role, message_content, %{original: response["output"]["message"]})
      | function_calls: function_calls
    }

    {:ok,
     LlmResponse.new(%{
       provider: :bedrock,
       status: :ok,
       main_response: message,
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

  @spec extract_text(list()) :: String.t() | nil
  defp extract_text(content) when is_list(content) do
    joined =
      content
      |> Enum.filter(&Map.has_key?(&1, "text"))
      |> Enum.map_join("", & &1["text"])

    if joined == "", do: nil, else: joined
  end
end
