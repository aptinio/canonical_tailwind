defmodule CanonicalTailwind.CanonicalizerTest do
  use ExUnit.Case, async: false

  import CanonicalTailwind.CanonicalizerHelpers

  alias CanonicalTailwind.Canonicalizer
  alias CanonicalTailwind.Config

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

    [worker] = running_workers()
    GenServer.stop(worker)

    assert Canonicalizer.canonicalize("py-3 p-1 px-3", []) == "p-3"
    assert [_worker] = running_workers()
  end

  test "stops a stale worker from a prior incomplete cold start" do
    Canonicalizer.canonicalize("p-0 flex", [])
    [stale_pid] = running_workers()

    # Simulate a prior cold start that registered the worker but crashed before
    # writing its persistent terms.
    erase_persistent_terms!()

    assert Canonicalizer.canonicalize("py-3 p-1 px-3", []) == "p-3"
    refute Process.alive?(stale_pid)
  end

  test "retries on a fresh worker when one stops on idle CLI death mid-call" do
    assert Canonicalizer.canonicalize("p-0 flex", []) == "flex p-0"

    [pid] = running_workers()
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

  test "routes to a separate warm CLI per resolved config" do
    Application.put_env(:tailwind, :other,
      args: ~w(--input=test/fixtures/other.css),
      cd: File.cwd!()
    )

    assert Canonicalizer.canonicalize("p-0 flex",
             canonical_tailwind: [profile: :canonical_tailwind]
           ) ==
             "flex p-0"

    assert Canonicalizer.canonicalize("py-3 p-1 px-3", canonical_tailwind: [profile: :other]) ==
             "p-3"

    workers = running_workers()
    assert length(workers) == 2
    assert Enum.all?(workers, &Process.alive?/1)

    # Each profile resolved to its own config and warm CLI, not a shared one.
    inputs = Enum.map(stored_configs(), &Enum.find(&1.args, fn arg -> arg =~ "--input=" end))
    assert "--input=test/fixtures/input.css" in inputs
    assert "--input=test/fixtures/other.css" in inputs
  end

  test "reuses one CLI for an env change that resolves to the same config" do
    assert Canonicalizer.canonicalize("p-0 flex", []) == "flex p-0"
    [worker] = running_workers()

    # :version_check is a :tailwind-package key we never read: it perturbs the raw
    # config without changing the resolved binary, args, or cd.
    Application.put_env(:tailwind, :version_check, false)

    assert Canonicalizer.canonicalize("py-3 p-1 px-3", []) == "p-3"

    assert running_workers() == [worker]
  end

  test "a first-caller that blocked on the resolve lock takes the published alias" do
    env = Application.get_all_env(:tailwind)
    config = Config.resolve!([], env)
    hash = :erlang.phash2(config)
    alias_key = {[], env}
    resolve_lock = {{Canonicalizer, :resolve, alias_key}, self()}

    # Hold the resolve lock so the call blocks just past its route miss, the way a
    # sibling cold start for the same raw term would.
    :global.set_lock(resolve_lock)
    task = Task.async(fn -> Canonicalizer.canonicalize("p-0 flex", []) end)
    Process.sleep(50)

    # Publish the config and alias while it waits, then release: the unblocked
    # caller must take the alias rather than re-resolve.
    :persistent_term.put({Canonicalizer, :config, hash}, config)
    :persistent_term.put({Canonicalizer, :alias, alias_key}, hash)
    :global.del_lock(resolve_lock)

    assert Task.await(task, :infinity) == "flex p-0"
    assert [_worker] = running_workers()
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
