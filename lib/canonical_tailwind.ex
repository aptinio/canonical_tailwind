defmodule CanonicalTailwind do
  @moduledoc false

  def render_attribute({"class", nil, _meta} = attr, _opts), do: attr

  def render_attribute({"class", {:string, value, meta}, attr_meta}, opts) do
    {"class", {:string, canonicalize(value, opts), meta}, attr_meta}
  end

  def render_attribute({"class", {:expr, value, meta}, attr_meta}, opts) do
    line_length = opts[:heex_line_length] || opts[:line_length] || 98
    {"class", {:expr, canonicalize_expr(value, opts, line_length), meta}, attr_meta}
  end

  defp canonicalize_expr(expr, opts, line_length) do
    {quoted, comments} =
      Code.string_to_quoted_with_comments!(expr,
        literal_encoder: &{:ok, {:__block__, &2, [&1]}},
        token_metadata: true,
        unescape: false
      )

    quoted
    |> canonicalize_ast(opts)
    |> Code.quoted_to_algebra(escape: false, comments: comments)
    |> Inspect.Algebra.format(line_length)
    |> IO.iodata_to_binary()
  end

  defp canonicalize_ast({:__block__, meta, [value]}, opts) when is_binary(value) do
    case meta[:delimiter] do
      delim when delim in ["\"", "\"\"\""] ->
        canonicalized =
          value
          |> canonicalize(opts)
          |> preserve_heredoc_newline(delim)

        {:__block__, meta, [canonicalized]}

      _ ->
        {:__block__, meta, [value]}
    end
  end

  defp canonicalize_ast({sigil, meta, [{:<<>>, bin_meta, [content]}, mods]}, opts)
       when sigil in [:sigil_s, :sigil_S] and is_binary(content) do
    canonicalized =
      content
      |> canonicalize(opts)
      |> preserve_heredoc_newline(meta[:delimiter])

    {sigil, meta, [{:<<>>, bin_meta, [canonicalized]}, mods]}
  end

  defp canonicalize_ast({:<<>>, meta, segments}, opts) do
    segments =
      Enum.map(segments, fn
        seg when is_binary(seg) -> seg
        interp -> canonicalize_ast(interp, opts)
      end)

    canonicalized =
      segments
      |> Enum.with_index()
      |> Enum.map(fn
        {binary, i} when is_binary(binary) ->
          prev_interp? = i > 0 and not is_binary(Enum.at(segments, i - 1))
          next_interp? = i < length(segments) - 1 and not is_binary(Enum.at(segments, i + 1))
          canonicalize_segment(binary, prev_interp?, next_interp?, opts)

        {interp, _i} ->
          interp
      end)

    {:<<>>, meta, canonicalized}
  end

  defp canonicalize_ast({left, right}, opts) do
    {canonicalize_ast(left, opts), canonicalize_ast(right, opts)}
  end

  defp canonicalize_ast({form, meta, args}, opts) when is_list(args) do
    {form, meta, Enum.map(args, &canonicalize_ast(&1, opts))}
  end

  defp canonicalize_ast(list, opts) when is_list(list) do
    Enum.map(list, &canonicalize_ast(&1, opts))
  end

  defp canonicalize_ast(other, _opts), do: other

  defp preserve_heredoc_newline(value, delim) when delim in ["\"\"\"", "'''"] do
    if String.ends_with?(value, "\n"), do: value, else: value <> "\n"
  end

  defp preserve_heredoc_newline(value, _delim), do: value

  defp canonicalize_segment(binary, prev_interp?, next_interp?, opts) do
    words = String.split(binary)

    if words == [] do
      binary
    else
      {prefix, words, suffix} = split_boundary_words(binary, words, prev_interp?, next_interp?)
      canonicalized = canonicalize(Enum.join(words, " "), opts)
      leading = if String.match?(binary, ~r/^\s/), do: " ", else: ""
      trailing = if String.match?(binary, ~r/\s$/), do: " ", else: ""

      parts =
        Enum.reject(
          [prefix, if(canonicalized != "", do: canonicalized), suffix],
          &is_nil/1
        )

      leading <> Enum.join(parts, " ") <> trailing
    end
  end

  defp split_boundary_words(binary, words, prev_interp?, next_interp?) do
    ignore_first = prev_interp? and not String.match?(binary, ~r/^\s/)
    ignore_last = next_interp? and not String.match?(binary, ~r/\s$/)

    {prefix, words} =
      if ignore_first, do: {hd(words), tl(words)}, else: {nil, words}

    {words, suffix} =
      if ignore_last and words != [],
        do: {Enum.drop(words, -1), List.last(words)},
        else: {words, nil}

    {prefix, words, suffix}
  end

  defp canonicalize(class_string, opts) do
    if String.trim(class_string) == "" do
      class_string
    else
      class_string
      |> String.replace("\n", " ")
      |> CanonicalTailwind.Pool.canonicalize(opts)
    end
  end
end
