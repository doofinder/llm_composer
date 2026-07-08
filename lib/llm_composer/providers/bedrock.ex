if Code.ensure_loaded?(ExAws) do
  defmodule LlmComposer.Providers.Bedrock do
    @moduledoc """
    Provider implementation for Amazon Bedrock.

    Handles chat completion requests through Amazon Bedrock Converse API. Any
    Bedrock compatible model can be used. To specify any model-specific options for
    the request, you can pass them in the `request_params` option and they will
    be merged into the base request that is prepared.

    ## Timeout configuration

    The HTTP receive timeout (how long to wait for data from Bedrock before giving
    up) can be tuned via application config. The lookup order is:

    1. `config :llm_composer, :bedrock, receive_timeout: <ms>` — Bedrock-specific override
    2. `config :llm_composer, :timeout, <ms>` — global llm_composer timeout
    3. Default: `30_000` ms (30 s)

    Example:

        config :llm_composer, :bedrock, receive_timeout: 60_000

    The timeout applies to all Mint-based requests (streaming and non-streaming).
    Finch regular (non-streaming) requests use Finch's own timeout configuration.

    ## Structured outputs

    `:response_schema` requests JSON output matching a schema. `:structured_output_strategy`
    picks how that's requested from Bedrock:

    * `:native` (default) - uses `outputConfig.textFormat.json_schema`. Only supported by
      some models (e.g. newer Anthropic Claude models on Bedrock or Nova models).
    * `:tool_use` - forces the model to call a synthesized `structured_response` tool whose
      input schema is `:response_schema`, then unwraps that call's arguments into the
      response content. Works on models without native structured-output support (Nova,
      Mistral, DeepSeek, older Qwen/Llama, etc.), since tool calling is supported far more
      broadly than `outputConfig` across Bedrock's model vendors. Note that this forces
      `toolChoice: {"any": {}}`, so combining it with `:functions` means the model could
      call one of those tools instead of `structured_response`.
    """
    @behaviour LlmComposer.Provider

    alias LlmComposer.Helpers
    alias LlmComposer.Message
    alias LlmComposer.ProviderResponse
    alias LlmComposer.Providers.Bedrock.StreamOperation
    alias LlmComposer.Providers.Utils

    @structured_response_tool_name "structured_response"

    @impl LlmComposer.Provider
    def name, do: :bedrock

    @impl LlmComposer.Provider
    @doc """
    Reference: https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_Converse.html
    Reference (stream): https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html
    """
    def run(messages, system_message, opts) do
      model = Keyword.get(opts, :model)
      stream = Keyword.get(opts, :stream_response, false)

      if model do
        messages
        |> build_request(system_message, opts)
        |> send_request(model, stream)
        |> handle_response(stream)
        |> wrap_response(opts)
      else
        {:error, :model_not_provided}
      end
    end

    @spec build_request(list(Message.t()), Message.t(), keyword()) :: map()
    defp build_request(messages, system_message, opts) do
      base_request = %{
        "messages" =>
          messages
          |> Enum.map(&format_message/1)
          |> merge_consecutive_tool_results(),
        "system" => [format_message(system_message)]
      }

      req_params = Keyword.get(opts, :request_params, %{})

      base_request
      |> Utils.merge_request_params(req_params)
      |> put_tool_config(opts)
      |> Utils.cleanup_body()
    end

    @spec put_tool_config(map(), keyword()) :: map()
    defp put_tool_config(base_request, opts) do
      tools =
        opts
        |> Keyword.get(:functions)
        |> Utils.get_tools(name())

      response_schema = Keyword.get(opts, :response_schema)
      strategy = Keyword.get(opts, :structured_output_strategy, :native)

      case {is_map(response_schema), strategy} do
        {true, :tool_use} ->
          put_tool_use_structured_output(base_request, response_schema, tools)

        {true, :native} ->
          base_request
          |> maybe_put_tools(tools)
          |> put_native_structured_output(response_schema)

        _ ->
          maybe_put_tools(base_request, tools)
      end
    end

    @spec maybe_put_tools(map(), [map()] | nil) :: map()
    defp maybe_put_tools(base_request, nil), do: base_request

    defp maybe_put_tools(base_request, tools) do
      Map.put(base_request, "toolConfig", %{"tools" => tools})
    end

    @spec put_native_structured_output(map(), map()) :: map()
    defp put_native_structured_output(base_request, response_schema) do
      Map.put(base_request, "outputConfig", %{
        "textFormat" => %{
          "type" => "json_schema",
          "structure" => %{
            "jsonSchema" => %{
              "name" => "response",
              "schema" => Helpers.json_engine().encode!(response_schema)
            }
          }
        }
      })
    end

    @spec put_tool_use_structured_output(map(), map(), [map()] | nil) :: map()
    defp put_tool_use_structured_output(base_request, response_schema, tools) do
      structured_tool = %{
        "toolSpec" => %{
          "name" => @structured_response_tool_name,
          "description" => "Return the structured response matching the required schema.",
          "inputSchema" => %{"json" => response_schema}
        }
      }

      Map.put(base_request, "toolConfig", %{
        "tools" => [structured_tool | tools || []],
        "toolChoice" => %{"any" => %{}}
      })
    end

    @spec send_request(map(), String.t(), boolean()) :: {:ok, term()} | {:error, term()}
    defp send_request(payload, model, true) do
      opts = Keyword.put(ex_aws_opts(), :http_opts, stream: true)

      payload
      |> StreamOperation.new(model)
      |> ExAws.request(opts)
    end

    defp send_request(payload, model, false) do
      operation = %ExAws.Operation.JSON{
        data: payload,
        headers: [{"Content-Type", "application/json"}],
        http_method: :post,
        path: "/model/#{model}/converse",
        service: :"bedrock-runtime"
      }

      ExAws.request(operation, ex_aws_opts())
    end

    @spec ex_aws_opts() :: keyword()
    defp ex_aws_opts do
      [service_override: :bedrock, http_client: LlmComposer.Providers.Bedrock.HttpClient]
    end

    @spec format_message(Message.t()) :: map()
    defp format_message(%Message{type: :system, content: content}) do
      %{"text" => content}
    end

    defp format_message(%Message{type: :tool_result, content: content, metadata: metadata}) do
      %{
        "role" => "user",
        "content" => [
          %{
            "toolResult" => %{
              "toolUseId" => metadata["tool_call_id"],
              "content" => [%{"text" => to_string(content)}]
            }
          }
        ]
      }
    end

    defp format_message(%Message{type: :assistant, metadata: metadata} = msg) do
      case get_in(metadata, [:original, "content"]) do
        original_content when is_list(original_content) ->
          %{"role" => "assistant", "content" => original_content}

        _ ->
          build_assistant_content(msg)
      end
    end

    defp format_message(%Message{type: role, content: content}) when is_binary(content) do
      %{"role" => Atom.to_string(role), "content" => [%{"text" => content}]}
    end

    defp format_message(%Message{type: role, content: content}) do
      %{"role" => Atom.to_string(role), "content" => content}
    end

    @spec build_assistant_content(Message.t()) :: map()
    defp build_assistant_content(%Message{content: content, function_calls: nil})
         when is_binary(content) do
      %{"role" => "assistant", "content" => [%{"text" => content}]}
    end

    defp build_assistant_content(%Message{content: content, function_calls: function_calls})
         when is_list(function_calls) do
      text_parts = if content && content != "", do: [%{"text" => content}], else: []

      tool_parts =
        Enum.map(function_calls, fn call ->
          arguments =
            if is_binary(call.arguments) do
              Helpers.json_engine().decode!(call.arguments)
            else
              call.arguments || %{}
            end

          %{"toolUse" => %{"toolUseId" => call.id, "name" => call.name, "input" => arguments}}
        end)

      %{"role" => "assistant", "content" => text_parts ++ tool_parts}
    end

    # Merges consecutive tool-result user messages into a single content block.
    # Bedrock requires all toolResult blocks for one assistant turn to be in one user turn.
    @spec merge_consecutive_tool_results([map()]) :: [map()]
    defp merge_consecutive_tool_results(messages) do
      messages
      |> Enum.reduce([], fn
        %{"role" => "user", "content" => [%{"toolResult" => _} | _] = parts},
        [%{"role" => "user", "content" => [%{"toolResult" => _} | _] = prev_parts} | rest] ->
          [%{"role" => "user", "content" => prev_parts ++ parts} | rest]

        msg, acc ->
          [msg | acc]
      end)
      |> Enum.reverse()
    end

    @spec handle_response({:ok, term()} | {:error, term()}, boolean()) ::
            {:ok, map()} | {:error, term()}
    defp handle_response({:ok, chunk_stream}, true) do
      # Lazily parse AWS Event Stream frames from the binary chunk stream.
      # Frame layout: [4B total_len][4B headers_len][4B prelude_crc][headers...][payload...][4B msg_crc]
      # Each extracted payload is a JSON-encoded binary (one per event).
      event_stream =
        Stream.transform(chunk_stream, <<>>, fn chunk, buffer ->
          extract_event_frames(buffer <> chunk, [])
        end)

      {:ok, %{stream: event_stream}}
    end

    defp handle_response({:ok, %{"output" => %{"message" => _}} = response}, false) do
      {:ok,
       %{
         response: response,
         input_tokens: get_in(response, ["usage", "inputTokens"]),
         output_tokens: get_in(response, ["usage", "outputTokens"])
       }}
    end

    defp handle_response({:error, resp}, _stream) do
      {:error, resp}
    end

    defp wrap_response(result, opts) do
      result
      |> ProviderResponse.Bedrock.new(opts)
      |> ProviderResponse.to_llm_response(opts)
    end

    # Extracts complete AWS Event Stream frames from a binary buffer.
    # Returns {payloads, remaining_buffer} for use with Stream.transform.
    # Incomplete frames are kept in the buffer for the next chunk.
    @spec extract_event_frames(binary(), [binary()]) :: {[binary()], binary()}
    defp extract_event_frames(
           <<total_len::32-big-unsigned, headers_len::32-big-unsigned, _prelude_crc::32,
             rest::binary>> = buffer,
           acc
         ) do
      payload_len = total_len - headers_len - 16

      if byte_size(rest) >= headers_len + payload_len + 4 do
        <<_headers::binary-size(headers_len), payload::binary-size(payload_len), _msg_crc::32,
          remaining::binary>> = rest

        extract_event_frames(remaining, [payload | acc])
      else
        {Enum.reverse(acc), buffer}
      end
    end

    defp extract_event_frames(buffer, acc), do: {Enum.reverse(acc), buffer}
  end
end
