defmodule LlmComposer.ProviderStreamChunk.Parser.OpenAIResponses do
  @moduledoc false

  alias LlmComposer.StreamChunk

  @doc """
  Parses a decoded Responses API SSE event into a normalized `StreamChunk`.

  Relevant event types:
  - `response.output_text.delta`         — text streaming delta
  - `response.function_call_arguments.delta` — tool-call arguments streaming delta
  - `response.output_item.added`         — tool-call item started (carries name + call_id)
  - `response.output_item.added/done`    — reasoning item summary blocks
  - `response.completed`                 — final event with usage
  - everything else                      — skipped
  """
  @spec parse(map(), atom(), keyword()) :: {:ok, StreamChunk.t()} | :skip
  def parse(%{"type" => "response.output_text.delta", "delta" => delta} = raw, provider, _opts)
      when is_binary(delta) and delta != "" do
    {:ok,
     %StreamChunk{
       provider: provider,
       type: :text_delta,
       text: delta,
       raw: raw
     }}
  end

  def parse(
        %{
          "type" => "response.function_call_arguments.delta",
          "delta" => delta
        } = raw,
        provider,
        _opts
      )
      when is_binary(delta) do
    tool_call = %{
      "type" => "function_call_arguments_delta",
      "call_id" => raw["call_id"],
      "arguments_delta" => delta
    }

    {:ok,
     %StreamChunk{
       provider: provider,
       type: :tool_call_delta,
       tool_call: tool_call,
       raw: raw
     }}
  end

  def parse(
        %{"type" => "response.output_item.added", "item" => %{"type" => "function_call"} = item} =
          raw,
        provider,
        _opts
      ) do
    tool_call = %{
      "type" => "function_call_started",
      "call_id" => item["call_id"],
      "name" => item["name"]
    }

    {:ok,
     %StreamChunk{
       provider: provider,
       type: :tool_call_delta,
       tool_call: tool_call,
       raw: raw
     }}
  end

  def parse(
        %{"type" => type, "item" => %{"type" => "reasoning"} = item} = raw,
        provider,
        _opts
      )
      when type in ["response.output_item.added", "response.output_item.done"] do
    reasoning = extract_reasoning_summary(item["summary"])
    reasoning_details = extract_reasoning_details(item["summary"])

    if reasoning in [nil, ""] and reasoning_details in [nil, []] do
      :skip
    else
      {:ok,
       %StreamChunk{
         provider: provider,
         type: :reasoning_delta,
         reasoning: reasoning,
         reasoning_details: reasoning_details,
         raw: raw
       }}
    end
  end

  def parse(%{"type" => "response.completed", "response" => response} = raw, provider, _opts) do
    usage = format_usage(response["usage"])
    reasoning = extract_completed_reasoning(response["output"])
    reasoning_details = extract_completed_reasoning_details(response["output"])

    {:ok,
     %StreamChunk{
       provider: provider,
       type: :done,
       reasoning: reasoning,
       reasoning_details: reasoning_details,
       usage: usage,
       metadata: %{finish_reason: "stop"},
       raw: raw
     }}
  end

  def parse(_, _, _), do: :skip

  @spec format_usage(map() | nil) :: StreamChunk.usage() | nil
  defp format_usage(%{
         "input_tokens" => input,
         "output_tokens" => output,
         "total_tokens" => total
       }) do
    %{input_tokens: input, output_tokens: output, total_tokens: total}
  end

  defp format_usage(_), do: nil

  defp extract_reasoning_summary(summary) when is_list(summary) do
    text =
      Enum.map_join(summary, "", fn
        %{"text" => text} when is_binary(text) -> text
        %{"summary" => text} when is_binary(text) -> text
        %{"content" => content} when is_binary(content) -> content
        _ -> ""
      end)

    case text do
      "" -> nil
      reasoning_summary -> reasoning_summary
    end
  end

  defp extract_reasoning_summary(_), do: nil

  defp extract_reasoning_details(summary) when is_list(summary) do
    case summary do
      [] -> nil
      details -> details
    end
  end

  defp extract_reasoning_details(_), do: nil

  defp extract_completed_reasoning(output) when is_list(output) do
    output
    |> Enum.filter(&(Map.get(&1, "type") == "reasoning"))
    |> Enum.flat_map(&Map.get(&1, "summary", []))
    |> extract_reasoning_summary()
  end

  defp extract_completed_reasoning(_), do: nil

  defp extract_completed_reasoning_details(output) when is_list(output) do
    details =
      output
      |> Enum.filter(&(Map.get(&1, "type") == "reasoning"))
      |> Enum.flat_map(&Map.get(&1, "summary", []))

    case details do
      [] -> nil
      _ -> details
    end
  end

  defp extract_completed_reasoning_details(_), do: nil
end
