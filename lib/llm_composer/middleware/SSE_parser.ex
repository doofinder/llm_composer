defmodule LlmComposer.Middleware.SSEParser do
  @moduledoc """
  Stateful SSE parser based on gemini_ex but returns raw :data strings
  Handles partial chunks across HTTP frames.
  """

  defstruct buffer: "", events: []

  @type t :: %__MODULE__{buffer: String.t()}

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec parse_chunk(String.t(), t()) :: {:ok, [map()], t()} | {:error, term()}
  def parse_chunk(chunk, %__MODULE__{buffer: buffer} = state) when is_binary(chunk) do
    full = buffer <> chunk
    {complete_events, remaining} = extract_events(full)

    parsed =
      complete_events
      |> Enum.map(&parse_event/1)
      |> Enum.reject(&is_nil/1)

    {:ok, parsed, %{state | buffer: remaining}}
  rescue
    e -> {:error, {:parse_error, e}}
  end

  @spec finalize(t()) :: {:ok, [map()]}
  def finalize(%__MODULE__{buffer: ""}), do: {:ok, []}
  def finalize(%__MODULE__{buffer: buf}), do: {:ok, [parse_event(buf)] |> Enum.reject(&is_nil/1)}

  # Stolen from https://github.com/nshkrdotcom/gemini_ex/blob/main/lib/gemini/sse/parser.ex
  defp extract_events(data) do
    parts = String.split(data, ~r/((\r\n)|((?<!\r)\n)|(\r(?!\n))){2}/)

    case parts do
      [single] -> {[], single}
      _ -> {Enum.drop(parts, -1) |> Enum.reject(&(&1 == "")), List.last(parts) || ""}
    end
  end

  defp parse_event(event_data) do
    event_data
    |> String.trim()
    |> parse_sse_lines()
    |> build_event()
  end

  defp parse_sse_lines(event_data) do
    event_data
    |> String.split("\n")
    |> Enum.reduce(%{data_lines: []}, &parse_line/2)
  end

  defp parse_line(raw, acc) do
    line = String.trim_trailing(raw, "\r")

    cond do
      line == "" -> acc
      String.starts_with?(line, ":") -> acc
      true -> parse_field(line, acc)
    end
  end

  defp parse_field(line, acc) do
    case String.split(line, ":", parts: 2) do
      [field, value] ->
        handle_field(String.trim(field), normalize(value), acc)

      _ ->
        acc
    end
  end

  defp normalize(" " <> v), do: v
  defp normalize(v), do: v

  defp handle_field("data", value, acc), do: Map.update!(acc, :data_lines, &(&1 ++ [value]))
  defp handle_field("event", v, acc), do: Map.put(acc, :event, v)
  defp handle_field("id", v, acc), do: Map.put(acc, :id, v)
  defp handle_field("retry", v, acc), do: Map.put(acc, :retry, v)
  defp handle_field(_, _, acc), do: acc

  defp build_event(%{data_lines: []}), do: nil

  defp build_event(%{data_lines: lines} = fields) do
    data = Enum.join(lines, "\n")

    fields
    |> Map.delete(:data_lines)
    |> Map.put(:data, data)
  end
end
