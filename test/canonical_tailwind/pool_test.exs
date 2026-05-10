defmodule CanonicalTailwind.PoolTest do
  use ExUnit.Case, async: false

  import CanonicalTailwind.PoolHelpers

  setup do
    tailwind_env = Application.get_all_env(:tailwind)

    reset_pool!()

    on_exit(fn ->
      reset_pool!()
      restore_tailwind_env(tailwind_env)
    end)
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

  test "stops stale workers from a prior incomplete cold start" do
    CanonicalTailwind.Pool.canonicalize("p-0 flex", [])

    name = Module.safe_concat(CanonicalTailwind.Canonicalizer, "0")
    stale_pid = GenServer.whereis(name)

    # Simulate a prior cold start that registered workers but crashed before
    # writing persistent terms.
    for key <- [:ready, :counter, :size, :config, :fingerprint] do
      :persistent_term.erase({CanonicalTailwind.Pool, key})
    end

    assert CanonicalTailwind.Pool.canonicalize("py-3 p-1 px-3", []) == "p-3"
    refute Process.alive?(stale_pid)
  end

  test "raises when formatter opts change after the pool starts" do
    assert CanonicalTailwind.Pool.canonicalize("p-0 flex", []) == "flex p-0"

    assert_raise ArgumentError, ~r/different canonical_tailwind configuration/, fn ->
      CanonicalTailwind.Pool.canonicalize("py-3 p-1 px-3", canonical_tailwind: [pool_size: 1])
    end
  end

  test "raises when tailwind application env changes after the pool starts" do
    profile_config = Application.fetch_env!(:tailwind, :canonical_tailwind)
    Application.delete_env(:tailwind, :canonical_tailwind)
    Application.put_env(:tailwind, :my_app, profile_config)

    assert CanonicalTailwind.Pool.canonicalize("p-0 flex", []) == "flex p-0"

    Application.put_env(:tailwind, :my_app,
      args: ~w(--input=test/fixtures/input.css),
      cd: File.cwd!(),
      env: %{"FOO" => "bar"}
    )

    assert_raise ArgumentError, ~r/different canonical_tailwind configuration/, fn ->
      CanonicalTailwind.Pool.canonicalize("py-3 p-1 px-3", [])
    end
  end

  defp restore_tailwind_env(tailwind_env) do
    :tailwind
    |> Application.get_all_env()
    |> Keyword.keys()
    |> Enum.each(&Application.delete_env(:tailwind, &1))

    Enum.each(tailwind_env, fn {key, value} ->
      Application.put_env(:tailwind, key, value)
    end)
  end
end
