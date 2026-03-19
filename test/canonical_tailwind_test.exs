defmodule CanonicalTailwindTest do
  use ExUnit.Case, async: true, group: :tailwind_env

  test "render_attribute/2" do
    # bare attribute is passed through
    attr = {"class", nil, %{line: 1, column: 1}}
    assert CanonicalTailwind.render_attribute(attr, []) == attr

    # string: canonicalizes the value
    canonicalize("p-0 flex", "flex p-0")
    canonicalize("flex", "flex")
    canonicalize("  p-0   flex ", "flex p-0")
    canonicalize("", "")
    canonicalize("   ", "   ")

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

    # expr: whitespace-only string is preserved
    canonicalize_expr(
      ~S/Enum.join([], " ")/,
      ~S/Enum.join([], " ")/
    )
  end

  defp canonicalize(input, expected) do
    assert {"class", {:string, ^expected, _}, _} =
             CanonicalTailwind.render_attribute({"class", {:string, input, %{}}, %{}}, [])
  end

  defp canonicalize_expr(input, expected) do
    assert {"class", {:expr, ^expected, _}, _} =
             CanonicalTailwind.render_attribute({"class", {:expr, input, %{}}, %{}}, [])
  end
end
