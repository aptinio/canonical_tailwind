defmodule CanonicalTailwind.SigilTest do
  use ExUnit.Case, async: true

  import CanonicalTailwind.Sigil

  test "expands to the body as a plain string" do
    assert ~TW"flex p-2" == "flex p-2"
    assert ~TW[flex p-2] == "flex p-2"
    assert ~TW"" == ""
  end

  test "does not canonicalize the body" do
    # ordering and whitespace are the formatter's job, never the macro's
    assert ~TW"p-0   flex" == "p-0   flex"
  end

  test "rejects interpolation at compile time" do
    assert_raise ArgumentError, ~r/does not support interpolation/, fn ->
      Code.eval_string(~S|import CanonicalTailwind.Sigil; ~TW"bg-#{color}"|)
    end
  end

  test "rejects modifiers at compile time" do
    assert_raise ArgumentError, ~r/does not accept modifiers/, fn ->
      Code.eval_string(~S|import CanonicalTailwind.Sigil; ~TW"flex"abc|)
    end
  end
end
