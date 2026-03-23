defmodule LlmComposer.ProviderStreamChunk.Parser.OpenAIResponses do
  @moduledoc false

  alias LlmComposer.Providers.OpenAIResponses.Reasoning
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
    reasoning = Reasoning.extract_summary(item["summary"])
    reasoning_details = Reasoning.extract_details(item["summary"])

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
    reasoning = Reasoning.extract_output_summary(response["output"])
    reasoning_details = Reasoning.extract_output_details(response["output"])

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
  defp format_usage(
         %{
           "input_tokens" => input,
           "output_tokens" => output,
           "total_tokens" => total
         } = usage
       ) do
    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: total,
      cached_tokens: get_in(usage, ["input_tokens_details", "cached_tokens"])
    }
  end

  defp format_usage(_), do: nil
end
