defmodule LlmComposer.ProviderResponse.Parser.Bedrock do
  @moduledoc false

  alias LlmComposer.Cost.CostAssembler
  alias LlmComposer.FunctionCall
  alias LlmComposer.FunctionCallExtractors
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @structured_response_tool_name "structured_response"

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

  def parse({:ok, %{response: response}}, :bedrock, opts) do
    content = response["output"]["message"]["content"]
    role = String.to_existing_atom(response["output"]["message"]["role"])

    {message_content, function_calls} =
      content
      |> FunctionCallExtractors.from_bedrock_content()
      |> extract_content(content, opts)

    message = %{
      Message.new(role, message_content, %{original: response["output"]["message"]})
      | function_calls: function_calls
    }

    cost_info = CostAssembler.get_cost_info(:bedrock, response, opts)

    {:ok,
     LlmResponse.new(%{
       provider: :bedrock,
       status: :ok,
       main_response: message,
       input_tokens: response["usage"]["inputTokens"],
       output_tokens: response["usage"]["outputTokens"],
       cost_info: cost_info,
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

  # When falling back to forced tool-use for structured output, the schema-conforming
  # JSON lives in the synthesized tool call's arguments rather than in a text block.
  @spec extract_content([FunctionCall.t()] | nil, list(), keyword()) ::
          {String.t() | nil, [FunctionCall.t()] | nil}
  defp extract_content(function_calls, content, opts) do
    with true <- is_map(Keyword.get(opts, :response_schema)),
         true <- Keyword.get(opts, :structured_output_strategy) == :tool_use,
         %FunctionCall{} = structured_call <-
           Enum.find(function_calls || [], &(&1.name == @structured_response_tool_name)) do
      remaining = Enum.reject(function_calls, &(&1.name == @structured_response_tool_name))
      {structured_call.arguments, if(remaining == [], do: nil, else: remaining)}
    else
      _ -> {extract_text(content), function_calls}
    end
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
