defmodule CanonicalTailwind.PortTest do
  use ExUnit.Case, async: true, group: :tailwind_env

  setup do
    original = Application.get_all_env(:tailwind)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:tailwind),
          do: Application.delete_env(:tailwind, key)

      Application.put_all_env(tailwind: original)
    end)
  end

  test "canonicalizes via the default profile and caches the port" do
    assert canonicalize("py-3 p-1 flex px-3 [display:_flex_]") == "flex p-3"
    assert canonicalize("") == ""

    port = Process.get({CanonicalTailwind.Port, :port})
    assert is_port(port)

    canonicalize("p-0")
    assert Process.get({CanonicalTailwind.Port, :port}) == port
  end

  test "uses explicit binary path" do
    opts = [
      canonical_tailwind: [
        binary: Tailwind.bin_path(),
        input: "test/fixtures/input.css",
        cd: "."
      ]
    ]

    assert CanonicalTailwind.Port.canonicalize("py-3 p-1 flex px-3 [display:_flex_]", opts) ==
             "flex p-3"
  end

  test "resolves input and cwd from profile without explicit options" do
    Application.put_env(:tailwind, :test_profile,
      args: ~w(--input=test/fixtures/input.css --output=/dev/null),
      cd: Path.expand("..", __DIR__)
    )

    opts = [canonical_tailwind: [profile: :test_profile]]

    assert CanonicalTailwind.Port.canonicalize("py-3 p-1 flex px-3 [display:_flex_]", opts) ==
             "flex p-3"
  end

  test "resolves nil when profile has no input or cwd" do
    Application.put_env(:tailwind, :bare_profile, args: [])

    opts = [canonical_tailwind: [profile: :bare_profile]]

    assert CanonicalTailwind.Port.canonicalize("py-3 p-1 flex px-3 [display:_flex_]", opts) ==
             "flex p-3"
  end

  test "raises when no tailwind profiles are configured" do
    for {key, _} <- Application.get_all_env(:tailwind), do: Application.delete_env(:tailwind, key)

    assert_raise RuntimeError, ~r/No tailwind profiles found/, fn ->
      CanonicalTailwind.Port.canonicalize("p-0", [])
    end
  end

  test "raises when multiple tailwind profiles exist without explicit profile" do
    Application.put_env(:tailwind, :extra_profile,
      args: ~w(--input=test/fixtures/input.css),
      cd: Path.expand("..", __DIR__)
    )

    assert_raise RuntimeError, ~r/Multiple tailwind profiles found/, fn ->
      CanonicalTailwind.Port.canonicalize("p-0", [])
    end
  end

  test "raises for unknown tailwind profile" do
    assert_raise ArgumentError, ~r/unknown tailwind profile/, fn ->
      CanonicalTailwind.Port.canonicalize("p-0", canonical_tailwind: [profile: :nonexistent])
    end
  end

  test "raises when tailwind CLI version is too old" do
    Application.put_env(:tailwind, :version, "4.1.0")

    assert_raise RuntimeError, ~r/requires tailwindcss >= 4\.2\.2/, fn ->
      CanonicalTailwind.Port.canonicalize("p-0", [])
    end
  end

  test "raises when explicit binary version is too old" do
    opts = [
      canonical_tailwind: [
        binary: Path.expand("../fixtures/tailwindcss-v4.2.1", __DIR__)
      ]
    ]

    assert_raise RuntimeError, ~r/requires tailwindcss >= 4\.2\.2/, fn ->
      CanonicalTailwind.Port.canonicalize("p-0", opts)
    end
  end

  defp canonicalize(class_string) do
    CanonicalTailwind.Port.canonicalize(class_string, [])
  end
end
