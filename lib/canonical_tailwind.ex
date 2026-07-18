defmodule CanonicalTailwind do
  @moduledoc false

  @behaviour Mix.Tasks.Format

  @impl Mix.Tasks.Format
  def features(_opts), do: [sigils: [:TW]]

  @impl Mix.Tasks.Format
  def format(contents, opts) do
    # Leave a body with interpolation untouched: the sigil_TW macro rejects it
    # at compile time, and we must not reorder tokens across a `#{...}`.
    if String.contains?(contents, "\#{") do
      contents
    else
      contents
      |> canonicalize(opts)
      |> preserve_heredoc_newline(opts[:opening_delimiter])
    end
  end

  def render_attribute({_name, nil, _meta} = attr, _opts), do: attr

  def render_attribute({name, {:string, value, meta}, attr_meta}, opts) do
    {name, {:string, canonicalize(value, opts), meta}, attr_meta}
  end

  def render_attribute({name, {:expr, value, meta}, attr_meta}, opts) do
    line_length = opts[:heex_line_length] || opts[:line_length] || 98
    {name, {:expr, canonicalize_expr(value, opts, line_length), meta}, attr_meta}
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

  defp canonicalize_ast({sigil, meta, [{:<<>>, bin_meta, segments}, mods]}, opts) when sigil in [:sigil_w, :sigil_W] do
    # A word-list sigil desugars to a list of independent classes: normalize each
    # word in place, but never sort or collapse them against each other. Modifiers
    # (~w()a, ~w()c) are canonicalized the same way; in a class attribute the words
    # are class data regardless of the produced element type.
    segments =
      segments
      |> canonicalize_segments(opts, :word_list)
      |> preserve_heredoc_newline_segments(meta[:delimiter])

    {sigil, meta, [{:<<>>, bin_meta, segments}, mods]}
  end

  defp canonicalize_ast({:<<>>, meta, segments}, opts) do
    {:<<>>, meta, canonicalize_segments(segments, opts, :class_string)}
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

  defp preserve_heredoc_newline_segments(segments, delim) when delim in ["\"\"\"", "'''"] do
    # A heredoc body always ends in a newline before the closing delimiter, so its
    # last segment is a binary; restore the newline the flattening replaced.
    case List.last(segments) do
      last when is_binary(last) ->
        List.replace_at(segments, -1, String.trim_trailing(last) <> "\n")

      _ ->
        segments
    end
  end

  defp preserve_heredoc_newline_segments(segments, _delim), do: segments

  defp canonicalize_segments(segments, opts, mode) do
    # In :word_list mode interpolations are opaque: a runtime value spliced into
    # the list could be whitespace-split into independent classes, so rewriting a
    # nested class string as a group would risk the same collapse as a bare list.
    segments =
      Enum.map(segments, fn
        seg when is_binary(seg) -> seg
        interp when mode == :word_list -> interp
        interp -> canonicalize_ast(interp, opts)
      end)

    segments
    |> Enum.with_index()
    |> Enum.map(fn
      {binary, i} when is_binary(binary) ->
        prev_interp? = i > 0 and not is_binary(Enum.at(segments, i - 1))
        next_interp? = i < length(segments) - 1 and not is_binary(Enum.at(segments, i + 1))
        canonicalize_segment(binary, prev_interp?, next_interp?, opts, mode)

      {interp, _i} ->
        interp
    end)
  end

  defp canonicalize_segment(binary, prev_interp?, next_interp?, opts, mode) do
    words = String.split(binary)

    if words == [] do
      binary
    else
      {prefix, words, suffix} = split_boundary_words(binary, words, prev_interp?, next_interp?)
      canonicalized = canonicalize_words(words, mode, opts)
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

  defp canonicalize_words(words, :class_string, opts), do: canonicalize(Enum.join(words, " "), opts)

  defp canonicalize_words(words, :word_list, opts), do: Enum.map_join(words, " ", &canonicalize(&1, opts))

  defp canonicalize(class_string, opts) do
    if String.trim(class_string) == "" do
      class_string
    else
      class_string
      |> String.replace("\n", " ")
      |> CanonicalTailwind.Canonicalizer.canonicalize(opts)
    end
  end
end
