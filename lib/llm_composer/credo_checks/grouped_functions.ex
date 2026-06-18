if Code.ensure_loaded?(Credo.Check) do
  defmodule LlmComposer.CredoChecks.GroupedFunctions do
    @moduledoc false

    use Credo.Check,
      base_priority: :normal,
      category: :readability,
      explanations: [
        check: """
        Public and private functions must be grouped, not interleaved.
        Keep all `def` clauses together and all `defp` clauses together.
        """
      ]

    alias Credo.IssueMeta
    alias Credo.SourceFile

    @impl Credo.Check
    def run(%SourceFile{} = source_file, params) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2), [])
      |> check_grouping(issue_meta)
    end

    defp traverse({kind, meta, [head | _]} = ast, acc) when kind in [:def, :defp] do
      name = extract_name(head)
      visibility = if kind == :def, do: :public, else: :private
      {ast, [{visibility, name, meta[:line]} | acc]}
    end

    defp traverse(ast, acc), do: {ast, acc}

    defp extract_name({:when, _, [head | _]}), do: extract_name(head)
    defp extract_name({name, _, _}) when is_atom(name), do: name
    defp extract_name(_), do: :unknown

    defp check_grouping(collected, issue_meta) do
      functions =
        collected
        |> Enum.reverse()
        |> Enum.dedup_by(fn {visibility, name, _line} -> {visibility, name} end)

      blocks = Enum.chunk_by(functions, fn {visibility, _, _} -> visibility end)

      duplicated_visibilities =
        blocks
        |> Enum.map(fn [{visibility, _, _} | _] -> visibility end)
        |> Enum.frequencies()
        |> Enum.filter(fn {_visibility, count} -> count > 1 end)
        |> Enum.map(fn {visibility, _} -> visibility end)

      blocks
      |> mark_offending_blocks(duplicated_visibilities)
      |> Enum.map(fn {visibility, name, line} ->
        build_issue(visibility, name, line, issue_meta)
      end)
    end

    defp mark_offending_blocks(blocks, duplicated_visibilities) do
      {offending, _seen} =
        Enum.reduce(blocks, {[], MapSet.new()}, fn [{visibility, name, line} | _], {acc, seen} ->
          if visibility in duplicated_visibilities and MapSet.member?(seen, visibility) do
            {[{visibility, name, line} | acc], seen}
          else
            {acc, MapSet.put(seen, visibility)}
          end
        end)

      Enum.reverse(offending)
    end

    defp build_issue(visibility, name, line_no, issue_meta) do
      format_issue(
        issue_meta,
        message:
          "#{visibility} function `#{name}` breaks grouping; keep all public and private functions grouped.",
        trigger: to_string(name),
        line_no: line_no
      )
    end
  end
end
