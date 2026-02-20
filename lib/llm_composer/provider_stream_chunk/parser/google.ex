defmodule LlmComposer.ProviderStreamChunk.Parser.Google do
  @moduledoc false

  alias LlmComposer.StreamChunk

  @spec parse(map(), atom(), keyword()) :: {:ok, StreamChunk.t()} | :skip
  def parse(%{"candidates" => [candidate | _]} = raw, _provider, _opts) do
    content = candidate["content"] || %{}
    parts = content["parts"] || []
    text = Enum.map_join(parts, "", &Map.get(&1, "text", ""))
    finish_reason = candidate["finishReason"] || candidate["finish_reason"]
    usage = format_usage(raw["usageMetadata"])

    type = if(finish_reason, do: :done, else: :text_delta)

    {:ok,
     %StreamChunk{
       provider: :google,
       type: type,
       text: text,
       usage: usage,
       metadata: %{finish_reason: finish_reason, role: content["role"]},
       raw: raw
     }}
  end

  def parse(_, _, _), do: :skip

  defp format_usage(%{
         "promptTokenCount" => prompt,
         "candidatesTokenCount" => candidate,
         "totalTokenCount" => total
       }) do
    %{input_tokens: prompt, output_tokens: candidate, total_tokens: total}
  end

  defp format_usage(_), do: nil
end
