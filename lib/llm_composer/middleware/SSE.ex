defmodule LlmComposer.Middleware.SSE do
  @behaviour Tesla.Middleware

  @default_content_types ["text/event-stream"]

  @impl Tesla.Middleware
  def call(env, next, opts) do
    with {:ok, env} <- Tesla.run(env, next) do
      decode(env, opts || [])
    end
  end

  defp decode(env, opts) do
    if decodable?(env, opts) do
      {:ok, %{env | body: decode_body(env.body, opts)}}
    else
      {:ok, env}
    end
  end

  defp decode_body(body, opts) when is_struct(body, Stream) or is_function(body) do
    parser = LlmComposer.Middleware.SSEParser.new()

    body
    |> Stream.chunk_while(
      parser,
      fn chunk, state ->
        case LlmComposer.Middleware.SSEParser.parse_chunk(chunk, state) do
          {:ok, events, new_state} -> {:cont, events, new_state}
          {:error, _} -> {:halt, chunk, state}
        end
      end,
      fn final_state ->
        {:ok, last_events} = LlmComposer.Middleware.SSEParser.finalize(final_state)
        {:cont, last_events, []}
      end
    )
    |> Stream.flat_map(& &1)
    |> Stream.flat_map(&only(&1, opts[:only]))
  end

  defp decode_body(binary, opts) when is_binary(binary) do
    parser = LlmComposer.Middleware.SSEParser.new()
    {:ok, events, updated_parser} = LlmComposer.Middleware.SSEParser.parse_chunk(binary, parser)
    {:ok, last} = LlmComposer.Middleware.SSEParser.finalize(updated_parser)
    (events ++ last) |> Enum.flat_map(&only(&1, opts[:only]))
  end

  defp only(%{data: data}, :data), do: [data]
  defp only(event, nil), do: [event]
  defp only(_, _), do: []

  defp decodable?(env, opts) do
    case Tesla.get_header(env, "content-type") do
      nil ->
        false

      ct ->
        Enum.any?(
          @default_content_types ++ Keyword.get(opts, :decode_content_types, []),
          &String.starts_with?(ct, &1)
        )
    end
  end
end
