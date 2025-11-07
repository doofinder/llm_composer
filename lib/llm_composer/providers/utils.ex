defmodule LlmComposer.Providers.Utils do
  @moduledoc false

  alias LlmComposer.Message

  @spec map_messages([Message.t()], atom) :: [map()]
  def map_messages(messages, provider \\ :open_ai)

  def map_messages(messages, :open_ai) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "content" => message}

      %Message{type: :system, content: message} when message in ["", nil] ->
        nil

      %Message{type: :system, content: message} ->
        %{"role" => "system", "content" => message}

      %Message{type: :assistant, content: message} ->
        %{"role" => "assistant", "content" => message}

      _other ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  def map_messages(messages, :open_router), do: map_messages(messages, :open_ai)

  def map_messages(messages, :google) do
    messages
    |> Stream.map(fn
      %Message{type: :user, content: message} ->
        %{"role" => "user", "parts" => [%{"text" => message}]}

      %Message{type: :assistant, content: message} ->
        %{"role" => "model", "parts" => [%{"text" => message}]}

      _other ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec cleanup_body(map()) :: map()
  def cleanup_body(body) do
    body
    |> Enum.reject(fn
      {_param, nil} -> true
      {_param, []} -> true
      _other -> false
    end)
    |> Map.new()
  end

  @spec get_tools([LlmComposer.Function.t()] | nil, atom) :: nil | [map()]
  def get_tools(nil, _provider), do: nil

  def get_tools(functions, provider) when is_list(functions) do
    Enum.map(functions, &transform_fn_to_tool(&1, provider))
  end

  @spec get_req_opts(keyword()) :: keyword()
  def get_req_opts(opts) do
    if Keyword.get(opts, :stream_response) do
      [adapter: [response: :stream]]
    else
      []
    end
  end

  @doc """
  Reads a configuration value for the given provider key.

  Priority order:
  1. Get from `opts` keyword list.
  2. Get from application config `:llm_composer`, provider_key.
  3. Use provided `default` value.
  """
  @spec get_config(atom, atom, keyword, any) :: any
  def get_config(provider_key, key, opts, default \\ nil) do
    case Keyword.get(opts, key) do
      nil ->
        :llm_composer
        |> Application.get_env(provider_key, [])
        |> Keyword.get(key, default)

      value ->
        value
    end
  end

  defp transform_fn_to_tool(%LlmComposer.Function{} = function, provider)
       when provider in [:open_ai, :ollama, :open_router] do
    %{
      type: "function",
      function: %{
        "name" => function.name,
        "description" => function.description,
        "parameters" => function.schema
      }
    }
  end

  defp transform_fn_to_tool(%LlmComposer.Function{} = function, :google) do
    %{
      "name" => function.name,
      "description" => function.description,
      "parameters" => function.schema
    }
  end
end
