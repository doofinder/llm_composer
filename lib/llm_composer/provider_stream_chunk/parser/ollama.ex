defmodule LlmComposer.ProviderStreamChunk.Parser.Ollama do
  @moduledoc false

  alias LlmComposer.StreamChunk

  @spec parse(map(), atom(), keyword()) :: {:ok, StreamChunk.t()} | :skip
  def parse(%{"message" => %{"content" => content, "role" => role}} = raw, _provider, _opts) do
    done = Map.get(raw, "done", false)
    type = if(done, do: :done, else: :text_delta)

    {:ok,
     %StreamChunk{
       provider: :ollama,
       type: type,
       text: content,
       metadata: %{role: role, done: done},
       raw: raw
     }}
  end

  def parse(_, _, _), do: :skip
end
