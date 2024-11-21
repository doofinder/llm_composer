defmodule LlmComposer.LlmResponse do
  @moduledoc """
  Module to parse and easily handle llm responses.
  """

  @llm_models [:open_ai, :ollama]

  alias LlmComposer.FunctionCall
  alias LlmComposer.Message

  @type t() :: %__MODULE__{
          actions: [[FunctionCall.t()]] | [FunctionCall.t()],
          input_tokens: pos_integer() | nil,
          main_response: Message.t(),
          output_tokens: pos_integer() | nil,
          previous_response: map() | nil,
          raw: map(),
          status: :ok | :error
        }

  defstruct [
    :actions,
    :main_response,
    :input_tokens,
    :output_tokens,
    :previous_response,
    :raw,
    :status
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

  def new(
        {status,
         %{actions: actions, response: %{"choices" => [first_choice | _]} = raw_response}},
        :open_ai
      ) do
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
end
