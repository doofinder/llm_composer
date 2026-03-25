defmodule LlmComposer.ProviderStreamChunk.Parser.Ollama do
  @moduledoc false

  alias LlmComposer.StreamChunk

  @spec parse(map(), atom(), keyword()) :: {:ok, StreamChunk.t()} | :skip
  def parse(%{"message" => %{"content" => content, "role" => role}} = raw, _provider, _opts) do
    done = Map.get(raw, "done", false)
    thinking = extract_thinking(raw)

    type =
      cond do
        done -> :done
        content not in [nil, ""] -> :text_delta
        thinking not in [nil, ""] -> :reasoning_delta
        true -> :text_delta
      end

    {:ok,
     %StreamChunk{
       provider: :ollama,
       type: type,
       text: content,
       reasoning: thinking,
       metadata: %{role: role, done: done},
       raw: raw
     }}
  end

  def parse(_, _, _), do: :skip

  defp extract_thinking(%{"message" => %{"thinking" => thinking}}) when is_binary(thinking),
    do: thinking

  defp extract_thinking(_raw), do: nil
end
