defmodule LlmComposer.ProviderResponse.Parser.Google do
  @moduledoc false

  alias LlmComposer.Cost.CostAssembler
  alias LlmComposer.FunctionCallExtractors
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @spec parse({:ok | :error, any()}, atom(), keyword()) ::
          {:ok, LlmResponse.t()} | {:error, term()}
  def parse({:error, %{body: body}}, _provider, _opts), do: {:error, body}

  def parse({:error, resp}, _provider, _opts), do: {:error, resp}

  def parse({:ok, %{response: response}}, :google, opts) do
    [first_candidate | _] = response["candidates"]
    content = first_candidate["content"]
    message_content = content["parts"] |> hd() |> Map.get("text")

    role =
      case content["role"] do
        "model" -> :assistant
        other -> String.to_existing_atom(other)
      end

    {input_tokens, output_tokens} = CostAssembler.extract_tokens(:google, response)
    cost_info = CostAssembler.get_cost_info(:google, response, opts)
    function_calls = FunctionCallExtractors.from_google_parts(content)

    {:ok,
     LlmResponse.new(%{
       provider: :google,
       status: :ok,
       main_response: Message.new(role, message_content, %{original: content}),
       function_calls: function_calls,
       input_tokens: input_tokens,
       output_tokens: output_tokens,
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
end
