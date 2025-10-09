defmodule LlmComposer.Providers.Utils do
  @moduledoc false

  alias LlmComposer.CostInfo
  alias LlmComposer.FunctionCall
  alias LlmComposer.Message
  alias LlmComposer.Providers.OpenRouter.PricingFetcher

  @json_mod if Code.ensure_loaded?(JSON), do: JSON, else: Jason

  @spec map_messages([Message.t()], atom) :: [map()]
  def map_messages(messages, provider \\ :open_ai)

  def map_messages(messages, :open_ai) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "content" => message}

      %Message{type: :system, content: message} when message in ["", nil] ->
        nil

      %Message{type: :system, content: message} ->
        %{"role" => "system", "content" => message}

      # reference to original "tool_calls"
      %Message{
        type: :assistant,
        content: nil,
        metadata: %{original: %{"tool_calls" => _tool_calls} = msg}
      } ->
        msg

      %Message{type: :assistant, content: message} ->
        %{"role" => "assistant", "content" => message}

      %Message{
        type: :function_result,
        content: message,
        metadata: %{
          fcall: %FunctionCall{
            id: call_id
          }
        }
      } ->
        %{"role" => "tool", "content" => message, "tool_call_id" => call_id}
    end)
    |> Enum.reject(&is_nil/1)
  end

  def map_messages(messages, :open_router), do: map_messages(messages, :open_ai)

  def map_messages(messages, :google) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "parts" => [%{"text" => message}]}

      # reference to original "tool_calls"
      %Message{
        type: :assistant,
        content: nil,
        metadata: %{original: %{"parts" => [%{"functionCall" => _}]} = msg}
      } ->
        msg

      %Message{type: :assistant, content: message} ->
        %{"role" => "model", "parts" => [%{"text" => message}]}

      %Message{
        type: :function_result,
        content: message,
        metadata: %{
          fcall: %FunctionCall{
            name: name
          }
        }
      } ->
        %{
          "role" => "user",
          "parts" => [
            %{"functionResponse" => %{"name" => name, "response" => %{"result" => message}}}
          ]
        }
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec cleanup_body(map()) :: map()
  def cleanup_body(body) do
    body
    |> Enum.reject(fn
      {_param, nil} -> true
      {_param, []} -> true
      _other -> false
    end)
    |> Map.new()
  end

  @spec get_tools([LlmComposer.Function.t()] | nil, atom) :: nil | [map()]
  def get_tools(nil, _provider), do: nil

  def get_tools(functions, provider) when is_list(functions) do
    Enum.map(functions, &transform_fn_to_tool(&1, provider))
  end

  @spec extract_actions(map()) :: nil | []
  def extract_actions(%{"choices" => choices}) when is_list(choices) do
    choices
    |> Enum.filter(&(&1["finish_reason"] == "tool_calls"))
    |> Enum.map(&get_action/1)
  end

  # google case
  def extract_actions(%{"candidates" => candidates}) when is_list(candidates) do
    candidates
    |> Enum.filter(fn
      %{"finishReason" => "STOP", "content" => %{"parts" => [%{"functionCall" => _data}]}} -> true
      _other -> false
    end)
    |> Enum.map(&get_action(&1, :google))
  end

  def extract_actions(_response), do: []

  @spec get_req_opts(keyword()) :: keyword()
  def get_req_opts(opts) do
    if Keyword.get(opts, :stream_response) do
      [adapter: [response: :stream]]
    else
      []
    end
  end

  @doc """
  Reads a configuration value for the given provider key.

  Priority order:
  1. Get from `opts` keyword list.
  2. Get from application config `:llm_composer`, provider_key.
  3. Use provided `default` value.
  """
  @spec get_config(atom, atom, keyword, any) :: any
  def get_config(provider_key, key, opts, default \\ nil) do
    case Keyword.get(opts, key) do
      nil ->
        :llm_composer
        |> Application.get_env(provider_key, [])
        |> Keyword.get(key, default)

      value ->
        value
    end
  end

  defp get_action(%{"message" => %{"tool_calls" => calls}}) do
    Enum.map(calls, fn call ->
      %FunctionCall{
        type: "function",
        id: call["id"],
        name: call["function"]["name"],
        arguments: @json_mod.decode!(call["function"]["arguments"])
      }
    end)
  end

  defp get_action(%{"content" => %{"parts" => parts}}, :google) do
    Enum.map(parts, fn
      %{"functionCall" => fcall} ->
        %FunctionCall{
          type: "function",
          id: nil,
          name: fcall["name"],
          arguments: fcall["args"]
        }
    end)
  end

  defp transform_fn_to_tool(%LlmComposer.Function{} = function, provider)
       when provider in [:open_ai, :ollama, :open_router] do
    %{
      type: "function",
      function: %{
        "name" => function.name,
        "description" => function.description,
        "parameters" => function.schema
      }
    }
  end

  defp transform_fn_to_tool(%LlmComposer.Function{} = function, :google) do
    %{
      "name" => function.name,
      "description" => function.description,
      "parameters" => function.schema
    }
  end

  @spec build_cost_info(atom(), keyword(), map()) :: CostInfo.t() | nil
  def build_cost_info(provider_name, opts, body) do
    if Keyword.get(opts, :track_costs) do
      {input_tokens, output_tokens} = extract_tokens(provider_name, body)
      model = get_model(provider_name, opts, body)
      pricing_opts = get_pricing_opts(provider_name, opts, body)

      CostInfo.new(provider_name, model, input_tokens, output_tokens, pricing_opts)
    end
  end

  # Extract tokens based on provider-specific response structure
  defp extract_tokens(:open_ai, body) do
    if is_map(body) and Map.has_key?(body, "usage") do
      input = get_in(body, ["usage", "prompt_tokens"]) || 0
      output = get_in(body, ["usage", "completion_tokens"]) || 0
      {input, output}
    else
      {nil, nil}
    end
  end

  # Same structure as OpenAI
  defp extract_tokens(:open_router, body), do: extract_tokens(:open_ai, body)

  defp extract_tokens(:google, body) do
    if is_map(body) and Map.has_key?(body, "usageMetadata") do
      usage = body["usageMetadata"] || %{}
      input = usage["promptTokenCount"] || 0
      output = usage["candidatesTokenCount"] || 0
      {input, output}
    else
      {nil, nil}
    end
  end

  # Get model based on provider-specific logic
  defp get_model(:open_ai, _opts, body), do: body["model"]
  defp get_model(:open_router, _opts, body), do: body["model"]
  defp get_model(:google, opts, _body), do: Keyword.get(opts, :model)

  # Get pricing options based on provider-specific logic
  defp get_pricing_opts(:open_router, opts, body) do
    # Prefer explicit pricing from opts if provided

    explicit =
      if not is_nil(opts[:input_price_per_million]) and
           not is_nil(opts[:output_price_per_million]) do
        Enum.reject(
          [
            input_price_per_million:
              opts[:input_price_per_million] && Decimal.new(opts[:input_price_per_million]),
            output_price_per_million:
              opts[:output_price_per_million] && Decimal.new(opts[:output_price_per_million]),
            currency: "USD"
          ],
          &is_nil(elem(&1, 1))
        )
      end

    if is_nil(explicit) or explicit == [] do
      # Fallback to dynamic pricing fetcher (may return nil)
      case PricingFetcher.fetch_pricing(body) do
        %{input_price_per_million: input_price, output_price_per_million: output_price} ->
          [
            input_price_per_million: input_price,
            output_price_per_million: output_price,
            currency: "USD"
          ]

        _ ->
          []
      end
    else
      explicit
    end
  end

  defp get_pricing_opts(provider, opts, _body) when provider in [:open_ai, :google] do
    Enum.reject(
      [
        input_price_per_million:
          opts[:input_price_per_million] && Decimal.new(opts[:input_price_per_million]),
        output_price_per_million:
          opts[:output_price_per_million] && Decimal.new(opts[:output_price_per_million]),
        currency: "USD"
      ],
      &is_nil(elem(&1, 1))
    )
  end
end
