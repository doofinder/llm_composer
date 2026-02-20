defmodule LlmComposer.ProviderResponse.Parser.OpenAI do
  @moduledoc false

  alias LlmComposer.Cost.CostAssembler
  alias LlmComposer.FunctionCallExtractors
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message
  require Logger

  @spec parse({:ok | :error, any()}, atom(), keyword()) ::
          {:ok, LlmResponse.t()} | {:error, term()}
  def parse({:error, %{body: body}}, _provider, _opts), do: {:error, body}

  def parse({:error, resp}, _provider, _opts), do: {:error, resp}

  def parse({:ok, %{response: stream}} = raw_result, provider, _opts) when is_function(stream) do
    {:ok,
     LlmResponse.new(%{
       provider: provider,
       status: :ok,
       stream: stream,
       raw: raw_result
     })}
  end

  def parse({:ok, %{response: response} = provider_response}, provider, opts) do
    log_fallback(response, opts)

    [first_choice | _rest] = response["choices"]
    main_response = get_in(first_choice, ["message"])

    message =
      main_response["role"]
      |> String.to_existing_atom()
      |> Message.new(main_response["content"], %{original: main_response})

    function_calls = FunctionCallExtractors.from_tool_calls(main_response)
    {input_tokens, output_tokens} = CostAssembler.extract_tokens(provider, response)
    cost_info = CostAssembler.get_cost_info(provider, response, opts)

    {:ok,
     LlmResponse.new(%{
       provider: provider,
       status: :ok,
       main_response: message,
       function_calls: function_calls,
       input_tokens: input_tokens,
       output_tokens: output_tokens,
       cost_info: cost_info,
       metadata: Map.get(provider_response, :metadata, %{}),
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

  defp log_fallback(response, opts) do
    if Keyword.get(opts, :models) && not is_function(response) do
      original_model = Keyword.get(opts, :model)
      used_model = response["model"]

      if original_model && used_model && original_model != used_model do
        Logger.warning("The '#{used_model}' model has been used instead of '#{original_model}'")
      end
    end
  end
end
