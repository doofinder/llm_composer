defmodule LlmComposer.ProviderStreamChunk.Parser.OpenAIRouter do
  @moduledoc false

  alias LlmComposer.StreamChunk

  @spec parse(map(), atom(), keyword()) :: {:ok, StreamChunk.t()} | :skip
  def parse(%{"choices" => [choice | _]} = raw, provider, _opts) do
    delta = choice["delta"] || %{}
    finish_reason = choice["finish_reason"]
    text = extract_text(delta)
    tool_call = Map.get(delta, "tool_call")
    usage = format_usage(raw["usage"])

    type =
      cond do
        not is_nil(finish_reason) -> :done
        Map.has_key?(delta, "tool_call") -> :tool_call_delta
        text not in [nil, ""] -> :text_delta
        true -> :unknown
      end

    {:ok,
     %StreamChunk{
       provider: provider,
       type: type,
       text: text,
       tool_call: tool_call,
       usage: usage,
       metadata: %{finish_reason: finish_reason},
       raw: raw
     }}
  end

  def parse(_, _, _), do: :skip

  defp extract_text(%{"content" => text}) when is_binary(text), do: text
  defp extract_text(_), do: nil

  defp format_usage(%{
         "prompt_tokens" => prompt,
         "completion_tokens" => completion,
         "total_tokens" => total
       }) do
    %{input_tokens: prompt, output_tokens: completion, total_tokens: total}
  end

  defp format_usage(_), do: nil
end
