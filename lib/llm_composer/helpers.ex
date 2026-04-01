defmodule LlmComposer.Helpers do
  @moduledoc """
  Provides helper functions for the `LlmComposer` module for handling language model responses.
  """

  @doc """
  Normalizes JSON-like decoded data into maps with string keys.

  This handles decoders that may emit ordered objects as lists of `{key, value}`
  tuples or maps keyed by atoms.
  """
  @spec normalize_json(term()) :: term()
  def normalize_json(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_key(key), normalize_json(value))
    end)
  end

  def normalize_json(data) when is_list(data) do
    if ordered_object?(data) do
      Enum.reduce(data, %{}, fn {key, value}, acc ->
        Map.put(acc, normalize_key(key), normalize_json(value))
      end)
    else
      Enum.map(data, &normalize_json/1)
    end
  end

  def normalize_json(data), do: data

  defp ordered_object?(data) do
    data != [] and
      Enum.all?(data, fn
        {key, _value} when is_binary(key) or is_atom(key) -> true
        _other -> false
      end)
  end

  @doc """
  Returns the configured JSON engine module.

  Reads `:json_engine` from application config. Defaults to `JSON` if available,
  otherwise falls back to `Jason`.
  """
  @spec json_engine() :: module()
  def json_engine do
    case Application.get_env(:llm_composer, :json_engine) do
      nil -> if Code.ensure_loaded?(JSON), do: JSON, else: Jason
      engine -> engine
    end
  end

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)
end
