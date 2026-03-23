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
    if streamed_chunks?(response) do
      {:ok,
       LlmResponse.new(%{
         provider: provider,
         status: :ok,
         stream: response,
         raw: %{provider_response | response: response}
       })}
    else
      log_fallback(response, opts)

      case fetch(response, ["choices", :choices], []) do
        [first_choice | _rest] ->
          main_response = fetch(first_choice, ["message", :message], %{})
          role = normalize_role(fetch(main_response, ["role", :role], "assistant"))
          content = normalize_content(fetch(main_response, ["content", :content]))

          base_msg = Message.new(role, content, %{original: main_response})

          message = %{
            base_msg
            | content: content,
              reasoning: fetch(main_response, ["reasoning", :reasoning]),
              reasoning_details: fetch(main_response, ["reasoning_details", :reasoning_details])
          }

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

        [] ->
          Logger.warning("[#{provider}] response had no choices: #{inspect(response)}")

          {:error,
           %{
             reason: :missing_choices,
             provider: provider,
             response: response
           }}
      end
    end
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
      used_model = fetch(response, ["model", :model])

      if original_model && used_model && original_model != used_model do
        Logger.warning("The '#{used_model}' model has been used instead of '#{original_model}'")
      end
    end
  end

  defp fetch(data, keys, default \\ nil)

  defp fetch(data, keys, default) when is_list(keys) do
    Enum.find_value(keys, default, fn key -> fetch(data, key, nil) end)
  end

  defp fetch(data, key, default) when is_map(data), do: Map.get(data, key, default)

  defp fetch(data, key, default) when is_list(data) do
    case Enum.find(data, fn
           {candidate, _value} -> candidate == key
           _other -> false
         end) do
      {_key, value} -> value
      nil -> default
    end
  end

  defp fetch(_data, _key, default), do: default

  defp normalize_role(role) when is_atom(role), do: role
  defp normalize_role(role) when is_binary(role), do: String.to_existing_atom(role)
  defp normalize_role(_role), do: :assistant

  defp normalize_content(content) when is_binary(content) or is_nil(content), do: content

  defp normalize_content(content) when is_list(content) do
    Enum.map_join(content, "", fn
      %{"text" => text} when is_binary(text) -> text
      %{text: text} when is_binary(text) -> text
      _ -> ""
    end)
  end

  defp normalize_content(_content), do: nil

  defp streamed_chunks?(response) when is_list(response), do: Enum.all?(response, &is_binary/1)
  defp streamed_chunks?(_response), do: false
end
