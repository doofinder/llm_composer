defmodule LlmComposer.ProviderStreamChunk.Parser.OpenAI do
  @moduledoc false

  alias LlmComposer.StreamChunk

  @spec parse(map(), atom(), keyword()) :: {:ok, StreamChunk.t()} | :skip
  def parse(%{"usage" => usage} = raw, provider, _opts) when is_map(usage) do
    {:ok,
     %StreamChunk{
       provider: provider,
       type: :usage,
       usage: format_usage(usage),
       raw: raw
     }}
  end

  def parse(%{"choices" => [choice | _]} = raw, provider, _opts) do
    delta = choice["delta"] || %{}
    finish_reason = choice["finish_reason"]
    text = extract_text(delta)
    reasoning = extract_reasoning(delta)
    reasoning_details = extract_reasoning_details(delta)
    tool_calls = Map.get(delta, "tool_calls")
    usage = format_usage(raw["usage"])

    type =
      cond do
        not is_nil(finish_reason) -> :done
        reasoning not in [nil, ""] or reasoning_details not in [nil, []] -> :reasoning_delta
        is_list(tool_calls) and tool_calls != [] -> :tool_call_delta
        text not in [nil, ""] -> :text_delta
        true -> :unknown
      end

    {:ok,
     %StreamChunk{
       provider: provider,
       type: type,
       text: text,
       reasoning: reasoning,
       reasoning_details: reasoning_details,
       tool_call: tool_calls,
       usage: usage,
       metadata: %{finish_reason: finish_reason},
       raw: raw
     }}
  end

  def parse(_, _, _), do: :skip

  defp extract_text(%{"content" => text}) when is_binary(text), do: text
  defp extract_text(_), do: nil

  defp extract_reasoning(%{"reasoning" => reasoning}) when is_binary(reasoning), do: reasoning
  defp extract_reasoning(_), do: nil

  defp extract_reasoning_details(%{"reasoning_details" => details}) when is_list(details),
    do: details

  defp extract_reasoning_details(_), do: nil

  defp format_usage(%{
         "prompt_tokens" => prompt,
         "completion_tokens" => completion,
         "total_tokens" => total
       }) do
    %{input_tokens: prompt, output_tokens: completion, total_tokens: total}
  end

  defp format_usage(_), do: nil
end
