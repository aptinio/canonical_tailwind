defmodule CanonicalTailwind.CanonicalizerTest do
  use ExUnit.Case, async: false

  import CanonicalTailwind.CanonicalizerHelpers

  alias CanonicalTailwind.Canonicalizer

  setup do
    tailwind_env = Application.get_all_env(:tailwind)

    reset!()

    on_exit(fn ->
      reset!()
      restore_tailwind_env(tailwind_env)
    end)
  end

  test "restarts a missing worker before using it" do
    assert Canonicalizer.canonicalize("p-0 flex", []) == "flex p-0"

    Canonicalizer.Worker
    |> GenServer.whereis()
    |> GenServer.stop()

    assert Canonicalizer.canonicalize("py-3 p-1 px-3", []) == "p-3"
    assert GenServer.whereis(Canonicalizer.Worker)
  end

  test "stops a stale worker from a prior incomplete cold start" do
    Canonicalizer.canonicalize("p-0 flex", [])
    stale_pid = GenServer.whereis(Canonicalizer.Worker)

    # Simulate a prior cold start that registered the worker but crashed before
    # writing persistent terms.
    for key <- [:ready, :config, :fingerprints] do
      :persistent_term.erase({Canonicalizer, key})
    end

    assert Canonicalizer.canonicalize("py-3 p-1 px-3", []) == "p-3"
    refute Process.alive?(stale_pid)
  end

  test "retries on a fresh worker when one stops on idle CLI death mid-call" do
    assert Canonicalizer.canonicalize("p-0 flex", []) == "flex p-0"

    pid = GenServer.whereis(Canonicalizer.Worker)
    port = :sys.get_state(pid).port

    # Stage the pick-to-call race: queue an idle-death exit status ahead of the
    # in-flight call so the worker stops with {:shutdown, {:cli_exited, _}}
    # *while the call is waiting on it*, then resume to let it process both.
    :sys.suspend(pid)
    send(pid, {port, {:exit_status, 0}})
    task = Task.async(fn -> Canonicalizer.canonicalize("py-3 p-1 px-3", []) end)
    Process.sleep(50)
    :sys.resume(pid)

    assert Task.await(task, :infinity) == "p-3"
  end

  test "raises when formatter opts change after the CLI starts" do
    assert Canonicalizer.canonicalize("p-0 flex", []) == "flex p-0"

    error =
      assert_raise ArgumentError, fn ->
        Canonicalizer.canonicalize("py-3 p-1 px-3", canonical_tailwind: [timeout: 1])
      end

    assert error.message =~ "different canonical_tailwind configuration"
    assert error.message =~ "mix format in each app separately"
  end

  test "raises when tailwind application env changes after the CLI starts" do
    profile_config = Application.fetch_env!(:tailwind, :canonical_tailwind)
    Application.delete_env(:tailwind, :canonical_tailwind)
    Application.put_env(:tailwind, :my_app, profile_config)

    assert Canonicalizer.canonicalize("p-0 flex", []) == "flex p-0"

    Application.put_env(:tailwind, :my_app,
      args: ~w(--input=test/fixtures/other.css),
      cd: File.cwd!()
    )

    assert_raise ArgumentError, ~r/different canonical_tailwind configuration/, fn ->
      Canonicalizer.canonicalize("py-3 p-1 px-3", [])
    end
  end

  test "tolerates a tailwind env change that resolves to the same config" do
    assert Canonicalizer.canonicalize("p-0 flex", []) == "flex p-0"

    # :version_check is a :tailwind-package key we never read: it perturbs the
    # config fingerprint without changing the resolved binary, args, or cd.
    Application.put_env(:tailwind, :version_check, false)

    assert Canonicalizer.canonicalize("py-3 p-1 px-3", []) == "p-3"

    # The new fingerprint is recorded as also-valid so it isn't re-resolved.
    fingerprints = :persistent_term.get({Canonicalizer, :fingerprints})
    assert MapSet.size(fingerprints) == 2
  end

  @tag capture_log: true
  test "surfaces a crashing worker as a clear error rather than an opaque exit" do
    binary = Path.expand("../fixtures/tailwindcss-dies-mid-request", __DIR__)
    opts = [canonical_tailwind: [binary: binary, cd: File.cwd!()]]

    assert_raise RuntimeError, ~r/exited.*before responding/s, fn ->
      Canonicalizer.canonicalize("p-0 flex", opts)
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
