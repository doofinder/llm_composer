defmodule LlmComposer.Middleware.SSE do
  @moduledoc """
  Tesla middleware that decodes Server-Sent Events (SSE) responses.

  Parses `text/event-stream` bodies into lists of maps with `:data`, `:event`, `:id`, etc.
  Supports streaming and handles partial chunks. Use the `:only` option to keep only a
  specific field (e.g. `only: :data`).
  """

  @behaviour Tesla.Middleware

  alias LlmComposer.Middleware.SSEParser

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
    parser = SSEParser.new()

    body
    |> Stream.chunk_while(
      parser,
      fn chunk, state ->
        case SSEParser.parse_chunk(chunk, state) do
          {:ok, events, new_state} -> {:cont, events, new_state}
          {:error, _} -> {:halt, chunk, state}
        end
      end,
      fn final_state ->
        {:ok, last_events} = SSEParser.finalize(final_state)
        {:cont, last_events, []}
      end
    )
    |> Stream.flat_map(& &1)
    |> Stream.flat_map(&only(&1, opts[:only]))
  end

  defp decode_body(binary, opts) when is_binary(binary) do
    parser = SSEParser.new()
    {:ok, events, updated_parser} = SSEParser.parse_chunk(binary, parser)
    {:ok, last} = SSEParser.finalize(updated_parser)
    Enum.flat_map(events ++ last, &only(&1, opts[:only]))
  end

  defp only(message, nil), do: [message]

  defp only(message, key) do
    case Map.get(message, key) do
      nil -> []
      val -> [val]
    end
  end

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
