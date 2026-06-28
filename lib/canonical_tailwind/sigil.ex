defmodule CanonicalTailwind.Sigil do
  @moduledoc false

  # The `~TW` sigil marks a string as a vouched Tailwind class list so the
  # formatter (CanonicalTailwind's `format/2`) canonicalizes it. For a valid
  # class list the macro is identity: `~TW"flex p-2"` compiles to the literal
  # `"flex p-2"` (it raises on interpolation or modifiers, which a class list
  # never has). Canonicalization happens only at `mix format` time, never at
  # compile or runtime, because it shells out to the Tailwind CLI and that
  # coupling has no place in a consumer's build.
  #
  # Importing this is needed only to keep `~TW` in your code; the formatter
  # acts on `~TW` without it.

  defmacro sigil_TW({:<<>>, _meta, [binary]}, []) when is_binary(binary) do
    if String.contains?(binary, "\#{") do
      raise ArgumentError,
            "~TW does not support interpolation. For a dynamic class, use a HEEx " <>
              "class={...} attribute or build the string with regular code."
    end

    binary
  end

  defmacro sigil_TW({:<<>>, _meta, []}, []), do: ""

  defmacro sigil_TW(_term, [_ | _] = modifiers) do
    raise ArgumentError, "~TW does not accept modifiers, got: #{modifiers}."
  end
end
