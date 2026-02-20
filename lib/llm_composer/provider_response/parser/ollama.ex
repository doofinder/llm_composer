defmodule LlmComposer.ProviderResponse.Parser.Ollama do
  @moduledoc false

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @spec parse({:ok | :error, any()}, atom(), keyword()) ::
          {:ok, LlmResponse.t()} | {:error, term()}
  def parse({:error, resp}, _provider, _opts), do: {:error, resp}

  def parse({:ok, %{response: response} = provider_response}, :ollama, _opts) do
    message =
      response["message"]["role"]
      |> String.to_existing_atom()
      |> Message.new(response["message"]["content"], %{original: response["message"]})

    {:ok,
     LlmResponse.new(%{
       provider: :ollama,
       status: :ok,
       main_response: message,
       cost_info: Map.get(provider_response, :cost_info),
       raw: response
     })}
  end

  def parse(result, provider, _opts) do
    {:error,
     %{
       reason: :unhandled_response_format,
       provider: provider,
       response: result
     }}
  end
end
