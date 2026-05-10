defmodule CanonicalTailwind.PoolTest do
  use ExUnit.Case, async: false

  import CanonicalTailwind.PoolHelpers

  setup do
    reset_pool!()
    on_exit(&reset_pool!/0)
  end

  test "restarts a missing worker before using it" do
    assert CanonicalTailwind.Pool.canonicalize("p-0 flex", []) == "flex p-0"

    pool_size = :persistent_term.get({CanonicalTailwind.Pool, :size})
    counter = :persistent_term.get({CanonicalTailwind.Pool, :counter})
    name = Module.safe_concat(CanonicalTailwind.Canonicalizer, "0")

    name
    |> GenServer.whereis()
    |> GenServer.stop()

    # Force the next pick to round-robin onto worker 0.
    :atomics.put(counter, 1, pool_size - 1)

    assert CanonicalTailwind.Pool.canonicalize("py-3 p-1 px-3", []) == "p-3"
    assert GenServer.whereis(name)
  end
end
