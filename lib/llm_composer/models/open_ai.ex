defmodule LlmComposer.Models.OpenAI do
  @moduledoc """
  Model implementation for OpenAI

  Basically it calls the OpenAI api for getting the chat responses.
  """
  @behaviour LlmComposer.Model

  use Tesla

  alias LlmComposer.Errors.MissingKeyError
  alias LlmComposer.FunctionCall
  alias LlmComposer.LlmResponse
  alias LlmComposer.Message

  @default_timeout 50_000

  plug(Tesla.Middleware.BaseUrl, "https://api.openai.com/v1")

  plug(Tesla.Middleware.JSON)

  plug(Tesla.Middleware.Retry,
    delay: :timer.seconds(1),
    max_delay: :timer.seconds(10),
    max_retries: 10,
    should_retry: fn
      {:ok, %{status: status}} when status in [429, 500, 503] -> true
      {:error, :closed} -> true
      _other -> false
    end
  )

  plug(Tesla.Middleware.Timeout,
    timeout: Application.get_env(:llm_composer, :timeout) || @default_timeout
  )

  @impl LlmComposer.Model
  def model_id, do: :open_ai

  @impl LlmComposer.Model
  @doc """
  Reference: https://platform.openai.com/docs/api-reference/chat/create
  """
  def run(messages, system_message, opts) do
    model = Keyword.get(opts, :model)

    headers = [
      {"Authorization", "Bearer " <> get_key()}
    ]

    if model do
      messages
      |> build_request(system_message, model, opts)
      |> then(&post("/chat/completions", &1, headers: headers))
      |> handle_response()
      |> LlmResponse.new(model_id())
    else
      {:error, :model_not_provided}
    end
  end

  defp build_request(messages, system_message, model, opts) do
    base_request = %{
      model: model,
      tools: get_tools(Keyword.get(opts, :functions)),
      messages:
        map_messages([
          system_message | messages
        ])
    }

    req_params = Keyword.get(opts, :request_params, %{})

    base_request
    |> Map.merge(req_params)
    |> cleanup_body()
  end

  defp map_messages(messages) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "content" => message}

      %Message{type: :system, content: message} when message in ["", nil] ->
        nil

      %Message{type: :system, content: message} ->
        %{"role" => "system", "content" => message}

      # reference to original "tool_calls"
      %Message{type: :assistant, content: nil, metadata: %{original: %{"tool_calls" => _} = msg}} ->
        msg

      %Message{type: :assistant, content: message} ->
        %{"role" => "assistant", "content" => message}

      %Message{
        type: :function_result,
        content: message,
        metadata: %{
          fcall: %FunctionCall{
            id: call_id
          }
        }
      } ->
        %{"role" => "tool", "content" => message, "tool_call_id" => call_id}
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec handle_response(Tesla.Env.result()) :: {:ok, map()} | {:error, term}
  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) when status in [200] do
    actions = extract_actions(body)
    {:ok, %{response: body, actions: actions}}
  end

  defp handle_response({:ok, resp}) do
    {:error, resp}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp cleanup_body(body) do
    body
    |> Enum.reject(fn
      {_param, nil} -> true
      {_param, []} -> true
      _other -> false
    end)
    |> Map.new()
  end

  @spec get_tools([LlmComposer.Function.t()] | nil) :: nil | [map()]
  defp get_tools(nil), do: nil

  defp get_tools(functions) when is_list(functions) do
    Enum.map(functions, &transform_fn_to_tool/1)
  end

  defp transform_fn_to_tool(%LlmComposer.Function{} = function) do
    %{
      type: "function",
      function: %{
        "name" => function.name,
        "description" => function.description,
        "parameters" => function.schema
      }
    }
  end

  @spec extract_actions(map()) :: nil | []
  defp extract_actions(%{"choices" => choices}) when is_list(choices) do
    choices
    |> Enum.filter(&(&1["finish_reason"] == "tool_calls"))
    |> Enum.map(&get_action/1)
  end

  defp extract_actions(_response), do: []

  defp get_action(%{"message" => %{"tool_calls" => calls}}) do
    Enum.map(calls, fn call ->
      %FunctionCall{
        type: "function",
        id: call["id"],
        name: call["function"]["name"],
        arguments: Jason.decode!(call["function"]["arguments"])
      }
    end)
  end

  defp get_key do
    case Application.get_env(:llm_composer, :openai_key) do
      nil -> raise MissingKeyError
      key -> key
    end
  end
end
