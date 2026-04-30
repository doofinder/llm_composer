defmodule LlmComposer.ProviderResponse.Parser.Ollama do
  @moduledoc false

  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @spec parse({:ok | :error, any()}, atom(), keyword()) ::
          {:ok, LlmResponse.t()} | {:error, term()}
  def parse({:error, resp}, _provider, _opts), do: {:error, resp}

  def parse({:ok, %{response: stream}} = raw_result, :ollama, _opts) when is_function(stream) do
    {:ok,
     LlmResponse.new(%{
       provider: :ollama,
       status: :ok,
       stream: stream,
       raw: raw_result
     })}
  end

  def parse({:ok, %{response: %Stream{} = stream}} = raw_result, :ollama, _opts) do
    {:ok,
     LlmResponse.new(%{
       provider: :ollama,
       status: :ok,
       stream: stream,
       raw: raw_result
     })}
  end

  def parse({:ok, %{response: response}} = raw_result, :ollama, _opts) when is_list(response) do
    if Enum.all?(response, &is_binary/1) do
      {:ok,
       LlmResponse.new(%{
         provider: :ollama,
         status: :ok,
         stream: response,
         raw: raw_result
       })}
    else
      {:error,
       %{
         reason: :unhandled_response_format,
         provider: :ollama,
         response: raw_result
       }}
    end
  end

  def parse({:ok, %{response: response} = provider_response}, :ollama, _opts) do
    message_data = response["message"]

    base_message =
      message_data["role"]
      |> String.to_existing_atom()
      |> Message.new(message_data["content"], %{original: message_data})

    message = %{base_message | reasoning: message_data["thinking"]}

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
