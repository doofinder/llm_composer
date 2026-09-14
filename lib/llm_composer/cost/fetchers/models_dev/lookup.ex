defmodule LlmComposer.Cost.Fetchers.ModelsDev.Lookup do
  @moduledoc """
  Pure lookup of a model's `"cost"` entry within a full models.dev dataset,
  including the region/date fallback chain `ModelsDev` needs.

  Kept separate from `ModelsDev` (and its main function public) so this logic
  can be unit-tested directly against a small in-memory dataset, without
  needing to fetch or cache anything — `ModelsDev` only ever calls this on a
  cache miss, against the freshly downloaded dataset.

  ## Region prefixes

  The region-prefix fallback defaults to `eu`, `us`, `ap`, and `global`
  (Bedrock's own regions), since that's what motivated it. It's a default, not
  a hardcoded assumption: override it per application with

      config :llm_composer, :models_dev, region_prefix_regex: ~r/^.../

  """

  alias LlmComposer.Providers.Utils

  require Logger

  @default_region_prefix_regex ~r/^(?:eu|us|ap|global)\./

  @doc """
  Looks up the raw `"cost"` map for `model` under `provider_key` in `data` (a
  full models.dev dataset shaped like `%{"openai" => %{"models" => %{...}}}`).

  Falls back to a region-stripped and then date-stripped model name if the
  exact name isn't indexed:
  1. Exact model name (some region-prefixed variants are indexed, e.g. `"eu.anthropic.claude-sonnet-4-6"`)
  2. Region prefix stripped (e.g. `"eu.amazon.nova-lite-v1:0"` → `"amazon.nova-lite-v1:0"`)
  3. Date suffix stripped (e.g. `"amazon.nova-lite-v1:0-2026-01-01"` → `"amazon.nova-lite-v1:0"`)

  Returns `nil` if no variant resolves.
  """
  @spec get_cost(map(), String.t(), String.t()) :: map() | nil
  def get_cost(data, provider_key, model) do
    case get_in(data, [provider_key, "models", model, "cost"]) do
      nil -> fallback_strip_region(data, provider_key, model)
      cost -> cost
    end
  end

  # Some Bedrock models have region prefixes (default eu., us., ap., global. —
  # see the moduledoc for overriding this) that are not indexed in models.dev.
  # Strip the prefix and retry before falling back further.
  defp fallback_strip_region(data, provider_key, model) do
    case strip_region_prefix(model) do
      ^model ->
        fallback_strip_date(data, provider_key, model)

      stripped_model ->
        Logger.debug(
          "Retrying models.dev pricing lookup for #{provider_key}/#{model} without region prefix (#{stripped_model})"
        )

        case get_in(data, [provider_key, "models", stripped_model, "cost"]) do
          nil -> fallback_strip_date(data, provider_key, stripped_model)
          cost -> cost
        end
    end
  end

  # APIs like OpenAI return snapshot model names with a date suffix (e.g. "gpt-5.4-mini-2026-03-17"),
  # but models.dev only indexes the base name. Strip the suffix and retry.
  defp fallback_strip_date(data, provider_key, model) do
    case strip_snapshot_date_suffix(model) do
      ^model ->
        nil

      fallback_model ->
        Logger.debug(
          "Retrying models.dev pricing lookup for #{provider_key}/#{model} with fallback #{fallback_model}"
        )

        get_in(data, [provider_key, "models", fallback_model, "cost"])
    end
  end

  defp strip_region_prefix(model) when is_binary(model) do
    Regex.replace(region_prefix_regex(), model, "")
  end

  defp strip_snapshot_date_suffix(model) when is_binary(model) do
    Regex.replace(~r/-\d{4}-\d{2}-\d{2}$/, model, "")
  end

  @spec region_prefix_regex() :: Regex.t()
  defp region_prefix_regex do
    Utils.get_config(:models_dev, :region_prefix_regex, [], @default_region_prefix_regex)
  end
end
