defmodule LlmComposer.LlmResponse do
  @moduledoc """
  Module to parse and easily handle llm responses.
  """

  alias LlmComposer.FunctionCall
  alias LlmComposer.Message

  @llm_providers [:open_ai, :ollama, :open_router, :bedrock, :google]

  @type t() :: %__MODULE__{
          actions: [[FunctionCall.t()]] | [FunctionCall.t()],
          input_tokens: pos_integer() | nil,
          main_response: Message.t() | nil,
          metadata: map(),
          output_tokens: pos_integer() | nil,
          previous_response: map() | nil,
          raw: map(),
          status: :ok | :error,
          stream: nil | Enum.t()
        }

  defstruct [
    :actions,
    :main_response,
    :input_tokens,
    :output_tokens,
    :previous_response,
    :raw,
    :status,
    :stream,
    metadata: %{}
  ]

  @type model_response :: Tesla.Env.result()

  @spec new(nil | model_response, atom()) :: {:ok, t()} | {:error, term()}
  def new(nil, _provider), do: {:error, :no_llm_response}

  def new({:error, %{body: body}}, provider) when provider in @llm_providers do
    {:error, body}
  end

  def new({:error, resp}, provider) when provider in @llm_providers do
    {:error, resp}
  end

  # Stream response case
  def new(
        {status, %{response: stream}} = raw_response,
        llm_provider
      )
      when llm_provider in [:open_ai, :open_router, :ollama, :google] and is_function(stream) do
    {:ok,
     %__MODULE__{
       actions: [],
       input_tokens: nil,
       output_tokens: nil,
       stream: stream,
       main_response: nil,
       raw: raw_response,
       status: status
     }}
  end

  def new(
        {status,
         %{actions: actions, response: %{"choices" => [first_choice | _]} = raw_response} =
           provider_response},
        llm_provider
      )
      when llm_provider in [:open_ai, :open_router] do
    main_response = get_in(first_choice, ["message"])

    response =
      main_response["role"]
      |> String.to_existing_atom()
      |> Message.new(main_response["content"], %{original: main_response})

    {:ok,
     %__MODULE__{
       actions: actions,
       input_tokens: get_in(raw_response, ["usage", "prompt_tokens"]),
       output_tokens: get_in(raw_response, ["usage", "completion_tokens"]),
       main_response: response,
       metadata: Map.get(provider_response, :metadata, %{}),
       raw: raw_response,
       status: status
     }}
  end

  def new(
        {status, %{actions: actions, response: %{"message" => message} = raw_response}},
        :ollama
      ) do
    response =
      message["role"]
      |> String.to_existing_atom()
      |> Message.new(message["content"], %{original: message})

    {:ok,
     %__MODULE__{
       actions: actions,
       main_response: response,
       raw: raw_response,
       status: status
     }}
  end

  def new({status, %{actions: actions, response: response}}, :bedrock) do
    [%{"text" => message_content}] = response["output"]["message"]["content"]
    role = String.to_existing_atom(response["output"]["message"]["role"])

    {:ok,
     %__MODULE__{
       actions: actions,
       input_tokens: response["usage"]["inputTokens"],
       output_tokens: response["usage"]["outputTokens"],
       main_response:
         Message.new(role, message_content, %{original: response["output"]["message"]}),
       raw: response,
       status: status
     }}
  end

  def new({status, %{actions: actions, response: response}}, :google) do
    [first_candidate | _] = response["candidates"]
    content = first_candidate["content"]
    [%{"text" => message_content}] = content["parts"]

    # Map "model" role to :assistant to match other providers
    role =
      case content["role"] do
        "model" -> :assistant
        other -> String.to_existing_atom(other)
      end

    usage = response["usageMetadata"]

    {:ok,
     %__MODULE__{
       actions: actions,
       input_tokens: usage["promptTokenCount"],
       output_tokens: usage["candidatesTokenCount"],
       main_response: Message.new(role, message_content, %{original: content}),
       raw: response,
       status: status
     }}
  end

  def new(_, provider), do: raise("provider #{provider} handling not implemented")
end
