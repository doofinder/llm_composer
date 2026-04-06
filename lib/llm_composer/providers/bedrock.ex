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

    alias LlmComposer.Helpers
    alias LlmComposer.Message
    alias LlmComposer.ProviderResponse
    alias LlmComposer.Providers.Bedrock.StreamOperation
    alias LlmComposer.Providers.Utils

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
      tools =
        opts
        |> Keyword.get(:functions)
        |> Utils.get_tools(name())

      tool_config = if tools, do: %{"toolConfig" => %{"tools" => tools}}, else: %{}

      base_request =
        Map.merge(
          %{
            "messages" =>
              messages
              |> Enum.map(&format_message/1)
              |> merge_consecutive_tool_results(),
            "system" => [format_message(system_message)]
          },
          tool_config
        )

      req_params = Keyword.get(opts, :request_params, %{})

      base_request
      |> Utils.merge_request_params(req_params)
      |> Utils.cleanup_body()
    end

    @spec send_request(map(), String.t(), boolean()) :: {:ok, term()} | {:error, term()}
    defp send_request(payload, model, true) do
      payload
      |> StreamOperation.new(model)
      |> ExAws.request(service_override: :bedrock, http_opts: [stream: true])
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
      base = [service_override: :bedrock]

      if Application.get_env(:ex_aws, :http_client) do
        base
      else
        Keyword.put(base, :http_client, LlmComposer.Providers.Bedrock.HttpClient)
      end
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
