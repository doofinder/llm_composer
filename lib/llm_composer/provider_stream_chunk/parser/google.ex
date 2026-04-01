defmodule LlmComposer.ProviderStreamChunk.Parser.Google do
  @moduledoc false

  alias LlmComposer.Cost.CostAssembler
  alias LlmComposer.FunctionCallExtractors
  alias LlmComposer.StreamChunk

  @spec parse(map(), atom(), keyword()) :: {:ok, StreamChunk.t()} | :skip
  def parse(%{"candidates" => [candidate | _]} = raw, _provider, opts) do
    content = candidate["content"] || %{}
    parts = content["parts"] || []
    text = extract_text(parts)
    tool_calls = FunctionCallExtractors.from_google_parts(content)
    finish_reason = candidate["finishReason"] || candidate["finish_reason"]
    usage = format_usage(raw["usageMetadata"])

    type =
      cond do
        not is_nil(finish_reason) ->
          :done

        text not in [nil, ""] ->
          :text_delta

        is_list(tool_calls) and tool_calls != [] ->
          :tool_call_delta

        true ->
          :unknown
      end

    {:ok,
     %StreamChunk{
       provider: :google,
       type: type,
       text: text,
       tool_call: tool_calls,
       usage: usage,
       cost_info: build_cost_info(type, raw, usage, opts),
       metadata: %{finish_reason: finish_reason, role: content["role"]},
       raw: raw
     }}
  end

  def parse(_, _, _), do: :skip

  defp extract_text(parts) do
    text = Enum.map_join(parts, "", &Map.get(&1, "text", ""))
    if text == "", do: nil, else: text
  end

  defp format_usage(
         %{
           "promptTokenCount" => prompt,
           "candidatesTokenCount" => candidate,
           "totalTokenCount" => total
         } = usage
       ) do
    %{
      input_tokens: prompt,
      output_tokens: candidate,
      total_tokens: total,
      cached_tokens: nil,
      reasoning_tokens: usage["thoughtsTokenCount"]
    }
  end

  defp format_usage(_), do: nil

  defp build_cost_info(:done, raw, usage, opts) when is_map(usage) do
    CostAssembler.get_cost_info(:google, raw, opts)
  end

  defp build_cost_info(_type, _raw, _usage, _opts), do: nil
end
