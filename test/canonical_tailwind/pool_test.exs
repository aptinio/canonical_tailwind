defmodule CanonicalTailwind.PoolTest do
  use ExUnit.Case, async: true, group: :tailwind_env

  setup do
    teardown_pool()
    original = Application.get_all_env(:tailwind)

    on_exit(fn ->
      teardown_pool()

      for {key, _} <- Application.get_all_env(:tailwind),
          do: Application.delete_env(:tailwind, key)

      Application.put_all_env(tailwind: original)
    end)
  end

  test "canonicalizes via the default profile and reuses the pool" do
    assert canonicalize("py-3 p-1 flex px-3 [display:_flex_]") == "flex p-3"
    assert canonicalize("") == ""

    pid = GenServer.whereis(:"Elixir.CanonicalTailwind.Canonicalizer.0")
    assert is_pid(pid)

    canonicalize("p-0")
    assert GenServer.whereis(:"Elixir.CanonicalTailwind.Canonicalizer.0") == pid
  end

  test "uses explicit binary path" do
    opts = [
      canonical_tailwind: [
        binary: Tailwind.bin_path(),
        input: "test/fixtures/input.css",
        cd: "."
      ]
    ]

    assert CanonicalTailwind.Pool.canonicalize("py-3 p-1 flex px-3 [display:_flex_]", opts) ==
             "flex p-3"
  end

  test "resolves input and cwd from profile without explicit options" do
    Application.put_env(:tailwind, :test_profile,
      args: ~w(--input=test/fixtures/input.css --output=/dev/null),
      cd: Path.expand("..", __DIR__)
    )

    opts = [canonical_tailwind: [profile: :test_profile]]

    assert CanonicalTailwind.Pool.canonicalize("py-3 p-1 flex px-3 [display:_flex_]", opts) ==
             "flex p-3"
  end

  test "resolves nil when profile has no input or cwd" do
    Application.put_env(:tailwind, :bare_profile, args: [])

    opts = [canonical_tailwind: [profile: :bare_profile]]

    assert CanonicalTailwind.Pool.canonicalize("py-3 p-1 flex px-3 [display:_flex_]", opts) ==
             "flex p-3"
  end

  test "raises when no tailwind profiles are configured" do
    for {key, _} <- Application.get_all_env(:tailwind), do: Application.delete_env(:tailwind, key)

    assert_raise RuntimeError, ~r/No tailwind profiles found/, fn ->
      CanonicalTailwind.Pool.canonicalize("p-0", [])
    end
  end

  test "raises when multiple tailwind profiles exist without explicit profile" do
    Application.put_env(:tailwind, :extra_profile,
      args: ~w(--input=test/fixtures/input.css),
      cd: Path.expand("..", __DIR__)
    )

    assert_raise RuntimeError, ~r/Multiple tailwind profiles found/, fn ->
      CanonicalTailwind.Pool.canonicalize("p-0", [])
    end
  end

  test "raises for unknown tailwind profile" do
    assert_raise ArgumentError, ~r/unknown tailwind profile/, fn ->
      CanonicalTailwind.Pool.canonicalize("p-0", canonical_tailwind: [profile: :nonexistent])
    end
  end

  test "raises when tailwind CLI version is too old" do
    Application.put_env(:tailwind, :version, "4.1.0")

    assert_raise RuntimeError, ~r/requires tailwindcss >= 4\.2\.2/, fn ->
      CanonicalTailwind.Pool.canonicalize("p-0", [])
    end
  end

  test "raises when explicit binary version is too old" do
    opts = [
      canonical_tailwind: [
        binary: Path.expand("../fixtures/tailwindcss-v4.2.1", __DIR__)
      ]
    ]

    assert_raise RuntimeError, ~r/requires tailwindcss >= 4\.2\.2/, fn ->
      CanonicalTailwind.Pool.canonicalize("p-0", opts)
    end
  end

  defp teardown_pool do
    for i <- 0..15 do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      name = Module.concat(CanonicalTailwind.Canonicalizer, "#{i}")
      if pid = GenServer.whereis(name), do: GenServer.stop(pid)
    end

    :persistent_term.erase({CanonicalTailwind.Pool, :ready})
    :persistent_term.erase({CanonicalTailwind.Pool, :counter})
    :persistent_term.erase({CanonicalTailwind.Pool, :size})
  end

  defp canonicalize(class_string) do
    CanonicalTailwind.Pool.canonicalize(class_string, [])
  end
end
