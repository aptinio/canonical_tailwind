defmodule CanonicalTailwindTest do
  use ExUnit.Case, async: false

  import CanonicalTailwind.CanonicalizerHelpers

  setup do
    reset!()
    on_exit(&reset!/0)
  end

  test "render_attribute/2" do
    assert running_workers() == []

    # bare attribute is passed through
    attr = {"class", nil, %{line: 1, column: 1}}
    assert CanonicalTailwind.render_attribute(attr, []) == attr

    # whitespace-only strings don't start the CLI
    canonicalize("", "")
    canonicalize("   ", "   ")

    assert running_workers() == []

    # any attribute name is canonicalized
    assert {"foo", {:string, "flex p-0", _}, _} =
             CanonicalTailwind.render_attribute({"foo", {:string, "p-0 flex", %{}}, %{}}, [])

    # string: canonicalizes the value
    canonicalize("p-0 flex", "flex p-0")
    canonicalize("flex", "flex")
    canonicalize("  p-0   flex ", "flex p-0")
    assert running_workers() != []

    # string: multi-line
    canonicalize("p-0 flex\npy-3 p-1 px-3", "flex p-3")

    # expr: string literal
    canonicalize_expr(~S/"p-0 flex"/, ~S/"flex p-0"/)

    # expr: empty string
    canonicalize_expr(~S/""/, ~S/""/)

    # expr: bare variable
    canonicalize_expr(~S/icon/, ~S/icon/)

    # expr: list of string literals
    canonicalize_expr(
      ~S/["p-0 flex", "py-3 p-1 px-3"]/,
      ~S/["flex p-0", "p-3"]/
    )

    # expr: list with variable
    canonicalize_expr(
      ~S/["p-0 flex", @extra]/,
      ~S/["flex p-0", @extra]/
    )

    # expr: conditional
    canonicalize_expr(
      ~S/if @active, do: "p-0 flex", else: "py-3 p-1 px-3"/,
      ~S/if @active, do: "flex p-0", else: "p-3"/
    )

    # expr: list with conditional
    canonicalize_expr(
      ~S/["p-0 flex", if(@active, do: "py-3 p-1 px-3")]/,
      ~S/["flex p-0", if(@active, do: "p-3")]/
    )

    # expr: word-list sigil: each word is a distinct element, never collapsed together
    canonicalize_expr(
      ~S/Enum.random(~w(w-100 w-140 w-60))/,
      ~S/Enum.random(~w(w-100 w-140 w-60))/
    )

    # expr: word-list sigil: words are normalized in place, order preserved
    canonicalize_expr(
      ~S/~w(hover:!underline px-4)/,
      ~S/~w(hover:underline! px-4)/
    )

    # expr: uppercase word-list sigil
    canonicalize_expr(
      ~S/~W(w-100 w-140)/,
      ~S/~W(w-100 w-140)/
    )

    # expr: word-list sigil modifier is preserved; the word is still normalized
    canonicalize_expr(
      ~S/~w(hover:!underline)a/,
      ~S/~w(hover:underline!)a/
    )

    # expr: word-list sigil with interpolation between independent words
    canonicalize_expr(
      ~S/~w(py-3 p-1 #{y} hover:!underline)/,
      ~S/~w(py-3 p-1 #{y} hover:underline!)/
    )

    # expr: word-list sigil whose body is a single interpolation is left untouched
    canonicalize_expr(
      ~S/~w(#{x})/,
      ~S/~w(#{x})/
    )

    # expr: word-list sigil word glued to an interpolation is one runtime word, left opaque
    canonicalize_expr(
      ~S/~w(hover:!underline#{x})/,
      ~S/~w(hover:!underline#{x})/
    )

    # expr: interpolations inside a word-list sigil are opaque: a nested class
    # string could be split into independent words at runtime, so it is left alone
    canonicalize_expr(
      ~S/~w(a #{if c, do: "py-3 p-1 px-3"})/,
      ~S/~w(a #{if c, do: "py-3 p-1 px-3"})/
    )

    canonicalize_expr(
      ~S/~w(a #{some_func("py-3 p-1 px-3")})/,
      ~S/~w(a #{some_func("py-3 p-1 px-3")})/
    )

    # expr: empty word-list sigil is preserved
    canonicalize_expr(
      ~S/~w()/,
      ~S/~w()/
    )

    # expr: string concatenation
    canonicalize_expr(
      ~S/"p-0 flex" <> " " <> "py-3 p-1 px-3"/,
      ~S/"flex p-0" <> " " <> "p-3"/
    )

    # expr: function call with class arg
    canonicalize_expr(
      ~S/merge_classes("p-0 flex", @extra)/,
      ~S/merge_classes("flex p-0", @extra)/
    )

    # expr: interpolation: standalone
    canonicalize_expr(
      ~S/"p-0 flex #{@extra}"/,
      ~S/"flex p-0 #{@extra}"/
    )

    # expr: interpolation: class suffix
    canonicalize_expr(
      ~S/"p-0 flex #{@color}-500"/,
      ~S/"flex p-0 #{@color}-500"/
    )

    # expr: interpolation: class prefix
    canonicalize_expr(
      ~S/"p-0 flex bg-#{@color}"/,
      ~S/"flex p-0 bg-#{@color}"/
    )

    # expr: interpolation: a word bounded by interpolations on both sides
    canonicalize_expr(
      ~S/"#{@a}-x-#{@b}"/,
      ~S/"#{@a}-x-#{@b}"/
    )

    # expr: interpolation: multiple
    canonicalize_expr(
      ~S/"p-0 flex #{@a} #{@b}"/,
      ~S/"flex p-0 #{@a} #{@b}"/
    )

    # expr: interpolation with nested strings
    canonicalize_expr(
      ~S/"p-0 flex #{if @active, do: "opacity-50", else: "cursor-pointer"}"/,
      ~S/"flex p-0 #{if @active, do: "opacity-50", else: "cursor-pointer"}"/
    )

    # expr: interpolation in a string canonicalizes nested class strings as a group
    canonicalize_expr(
      ~S/"p-0 flex #{if @active, do: "py-3 p-1 px-3"}"/,
      ~S/"flex p-0 #{if @active, do: "p-3"}"/
    )

    # expr: whitespace-only string is preserved
    canonicalize_expr(
      ~S/Enum.join([], " ")/,
      ~S/Enum.join([], " ")/
    )

    # expr: bare heredoc
    canonicalize_expr(
      ~s/"""\npy-3 p-1 px-3\n"""/,
      ~s/"""\np-3\n"""/
    )

    # expr: heredoc sigil (double-quote)
    canonicalize_expr(
      ~s/~s"""\npy-3 p-1 px-3\n"""/,
      ~s/~s"""\np-3\n"""/
    )

    # expr: heredoc sigil (single-quote)
    canonicalize_expr(
      "~s'''\npy-3 p-1 px-3\n'''",
      "~s'''\np-3\n'''"
    )

    # expr: word-list heredoc: words normalized independently, trailing newline kept
    canonicalize_expr(
      ~s/~w"""\nhover:!underline px-4\n"""/,
      ~s/~w"""\nhover:underline! px-4\n"""/
    )

    # expr: multi-line word-list heredoc flattens to one line, staying a valid heredoc
    canonicalize_expr(
      ~s/~w"""\nhover:!underline\npx-4\n"""/,
      ~s/~w"""\nhover:underline! px-4\n"""/
    )

    # expr: single-quote word-list heredoc
    canonicalize_expr(
      "~w'''\nhover:!underline px-4\n'''",
      "~w'''\nhover:underline! px-4\n'''"
    )
  end

  test "features/1" do
    assert CanonicalTailwind.features([]) == [sigils: [:TW]]
  end

  test "format/2" do
    assert running_workers() == []

    # whitespace-only bodies don't start the CLI
    canonicalize_sigil("", "")
    canonicalize_sigil("   ", "   ")
    assert running_workers() == []

    # canonicalizes the sigil body
    canonicalize_sigil("p-0 flex", "flex p-0")
    canonicalize_sigil("  p-0   flex ", "flex p-0")
    assert running_workers() != []

    # collapses conflicting utilities
    canonicalize_sigil("py-3 p-1 px-3", "p-3")

    # a body with interpolation is left untouched (the macro rejects it at compile time)
    canonicalize_sigil(~S|bg-#{color} flex|, ~S|bg-#{color} flex|)

    # a non-heredoc delimiter gets no trailing newline
    canonicalize_sigil("p-0 flex", "flex p-0", opening_delimiter: "[")

    # heredoc body: newlines collapse, the trailing newline is preserved
    canonicalize_sigil("p-0 flex\npy-3 p-1 px-3\n", "flex p-3\n", opening_delimiter: ~S/"""/)

    # the single-quote heredoc delimiter is handled too
    canonicalize_sigil("p-0 flex\n", "flex p-0\n", opening_delimiter: "'''")

    # whitespace-only heredoc body is preserved untouched
    canonicalize_sigil("\n", "\n", opening_delimiter: ~S/"""/)
  end

  test "format/2 round-trips idempotently through the Elixir formatter" do
    sigils =
      for {:sigils, names} <- CanonicalTailwind.features([]),
          name <- names,
          do: {name, &CanonicalTailwind.format/2}

    format = fn source ->
      source
      |> Code.format_string!(sigils: sigils)
      |> IO.iodata_to_binary()
    end

    cases = [
      # string
      {~S/x = ~TW"p-0   flex"/, ~S/x = ~TW"flex p-0"/},
      # bracket-delimited list form
      {~S/x = ~TW[p-0 flex]/, ~S/x = ~TW[flex p-0]/},
      # as a list element among calls and conditionals (the list-with-calls slice)
      {~S/x = [base(), ~TW"p-0 flex", active? && "m-1"]/, ~S/x = [base(), ~TW"flex p-0", active? && "m-1"]/},
      # heredoc body re-wraps without breaking the closing delimiter
      {~s(x = ~TW"""\np-0 flex\npy-3 p-1 px-3\n"""), ~s(x = ~TW"""\nflex p-3\n""")}
    ]

    for {source, expected} <- cases do
      once = format.(source)
      assert once == expected
      assert format.(once) == once
    end
  end

  defp canonicalize(input, expected) do
    assert {"class", {:string, ^expected, _}, _} =
             CanonicalTailwind.render_attribute({"class", {:string, input, %{}}, %{}}, [])
  end

  defp canonicalize_expr(input, expected) do
    assert {"class", {:expr, ^expected, _}, _} =
             CanonicalTailwind.render_attribute({"class", {:expr, input, %{}}, %{}}, [])
  end

  defp canonicalize_sigil(input, expected, opts \\ []) do
    assert CanonicalTailwind.format(input, [sigil: :TW] ++ opts) == expected
  end
end
