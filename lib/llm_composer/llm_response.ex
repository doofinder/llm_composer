defmodule LlmComposer.LlmResponse do
  @moduledoc """
  Module to parse and easily handle llm responses.
  """

  alias LlmComposer.Cost.CostAssembler
  alias LlmComposer.CostInfo
  alias LlmComposer.FunctionCall
  alias LlmComposer.Message

  @llm_providers [:open_ai, :ollama, :open_router, :bedrock, :google]

  @type provider() :: :open_ai | :ollama | :open_router | :bedrock | :google

  @type t() :: %__MODULE__{
          actions: [[FunctionCall.t()]] | [FunctionCall.t()],
          cost_info: CostInfo.t() | nil,
          input_tokens: pos_integer() | nil,
          main_response: Message.t() | nil,
          metadata: map(),
          output_tokens: pos_integer() | nil,
          previous_response: map() | nil,
          provider: provider(),
          raw: map(),
          status: :ok | :error,
          stream: nil | Enum.t()
        }

  defstruct [
    :actions,
    :cost_info,
    :main_response,
    :input_tokens,
    :output_tokens,
    :previous_response,
    :provider,
    :raw,
    :status,
    :stream,
    metadata: %{}
  ]

  @type model_response :: Tesla.Env.result()

  @spec new(nil | model_response, atom(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(response, provider, opts \\ [])

  def new(nil, _provider, _opts), do: {:error, :no_llm_response}

  def new({:error, %{body: body}}, provider, _opts) when provider in @llm_providers do
    {:error, body}
  end

  def new({:error, resp}, provider, _opts) when provider in @llm_providers do
    {:error, resp}
  end

  # Stream response case
  def new(
        {status, %{response: stream}} = raw_response,
        llm_provider,
        _opts
      )
      when llm_provider in [:open_ai, :open_router, :ollama, :google] and is_function(stream) do
    {:ok,
     %__MODULE__{
       actions: [],
       cost_info: nil,
       input_tokens: nil,
       output_tokens: nil,
       stream: stream,
       provider: llm_provider,
       main_response: nil,
       raw: raw_response,
       status: status
     }}
  end

  def new(
        {status,
         %{actions: actions, response: %{"choices" => [first_choice | _tail]} = raw_response} =
           provider_response},
        llm_provider,
        opts
      )
      when llm_provider in [:open_ai, :open_router] do
    main_response = get_in(first_choice, ["message"])

    response =
      main_response["role"]
      |> String.to_existing_atom()
      |> Message.new(main_response["content"], %{original: main_response})

    {input_tokens, output_tokens} = CostAssembler.extract_tokens(llm_provider, raw_response)
    cost_info = CostAssembler.get_cost_info(llm_provider, raw_response, opts)

    {:ok,
     %__MODULE__{
       actions: actions,
       cost_info: cost_info,
       input_tokens: input_tokens,
       output_tokens: output_tokens,
       main_response: response,
       metadata: Map.get(provider_response, :metadata, %{}),
       provider: llm_provider,
       raw: raw_response,
       status: status
     }}
  end

  def new(
        {status,
         provider_response = %{actions: actions, response: %{"message" => message} = raw_response}},
        :ollama = provider,
        _opts
      ) do
    response =
      message["role"]
      |> String.to_existing_atom()
      |> Message.new(message["content"], %{original: message})

    {:ok,
     %__MODULE__{
       actions: actions,
       cost_info: Map.get(provider_response, :cost_info),
       main_response: response,
       provider: provider,
       raw: raw_response,
       status: status
     }}
  end

  def new(
        {status, %{actions: actions, response: response} = provider_response},
        :bedrock = provider,
        _opts
      ) do
    [%{"text" => message_content}] = response["output"]["message"]["content"]
    role = String.to_existing_atom(response["output"]["message"]["role"])

    {:ok,
     %__MODULE__{
       actions: actions,
       cost_info: Map.get(provider_response, :cost_info),
       input_tokens: response["usage"]["inputTokens"],
       output_tokens: response["usage"]["outputTokens"],
       main_response:
         Message.new(role, message_content, %{original: response["output"]["message"]}),
       provider: provider,
       raw: response,
       status: status
     }}
  end

  def new(
        {status, %{actions: actions, response: response}},
        :google = provider,
        opts
      ) do
    [first_candidate | _] = response["candidates"]
    content = first_candidate["content"]

    message_content =
      content["parts"]
      |> hd()
      |> Map.get("text")

    # Map "model" role to :assistant to match other providers
    role =
      case content["role"] do
        "model" -> :assistant
        other -> String.to_existing_atom(other)
      end

    {input_tokens, output_tokens} = CostAssembler.extract_tokens(provider, response)
    cost_info = CostAssembler.get_cost_info(provider, response, opts)

    {:ok,
     %__MODULE__{
       actions: actions,
       cost_info: cost_info,
       input_tokens: input_tokens,
       output_tokens: output_tokens,
       main_response: Message.new(role, message_content, %{original: content}),
       provider: provider,
       raw: response,
       status: status
     }}
  end

  def new(_response, provider, _opts),
    do: raise("provider #{provider} handling not implemented")
end
