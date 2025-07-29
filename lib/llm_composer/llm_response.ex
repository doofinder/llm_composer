defmodule LlmComposer.LlmResponse do
  @moduledoc """
  Module to parse and easily handle llm responses.
  """

  alias LlmComposer.FunctionCall
  alias LlmComposer.Message

  @llm_models [:open_ai, :ollama, :open_router, :bedrock]

  @type t() :: %__MODULE__{
          actions: [[FunctionCall.t()]] | [FunctionCall.t()],
          input_tokens: pos_integer() | nil,
          main_response: Message.t() | nil,
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
    :stream
  ]

  @type model_response :: Tesla.Env.result()

  @spec new(nil | model_response, atom()) :: {:ok, t()} | {:error, term()}
  def new(nil, _model), do: {:error, :no_llm_response}

  def new({:error, %{body: body}}, model) when model in @llm_models do
    {:error, body}
  end

  def new({:error, resp}, model) when model in @llm_models do
    {:error, resp}
  end

  # Stream response case
  def new(
        {status, %{response: stream}} = raw_response,
        llm_model
      )
      when llm_model in [:open_ai, :open_router] and is_function(stream) do
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
         %{actions: actions, response: %{"choices" => [first_choice | _]} = raw_response}},
        llm_model
      )
      when llm_model in [:open_ai, :open_router] do
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
end
