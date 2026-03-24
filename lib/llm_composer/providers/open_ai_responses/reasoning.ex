defmodule LlmComposer.Providers.OpenAIResponses.Reasoning do
  @moduledoc false

  @doc false
  @spec extract_summary(list() | nil) :: String.t() | nil
  def extract_summary(summary) when is_list(summary) do
    text =
      Enum.map_join(summary, "", fn
        %{"text" => text} when is_binary(text) -> text
        %{"summary" => text} when is_binary(text) -> text
        %{"content" => content} when is_binary(content) -> content
        _ -> ""
      end)

    case text do
      "" -> nil
      reasoning_summary -> reasoning_summary
    end
  end

  def extract_summary(_summary), do: nil

  @doc false
  @spec extract_details(list() | nil) :: list() | nil
  def extract_details([]), do: nil
  def extract_details(summary) when is_list(summary), do: summary
  def extract_details(_summary), do: nil

  @doc false
  @spec extract_output_summary(list() | nil) :: String.t() | nil
  def extract_output_summary(output_items) when is_list(output_items) do
    output_items
    |> reasoning_summary_items()
    |> extract_summary()
  end

  def extract_output_summary(_output_items), do: nil

  @doc false
  @spec extract_output_details(list() | nil) :: list() | nil
  def extract_output_details(output_items) when is_list(output_items) do
    output_items
    |> reasoning_summary_items()
    |> extract_details()
  end

  def extract_output_details(_output_items), do: nil

  defp reasoning_summary_items(output_items) do
    output_items
    |> Enum.filter(&(Map.get(&1, "type") == "reasoning"))
    |> Enum.flat_map(&Map.get(&1, "summary", []))
  end
end
