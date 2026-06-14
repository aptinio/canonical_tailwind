defmodule CanonicalTailwind.Canonicalizer do
  @moduledoc false

  alias CanonicalTailwind.Canonicalizer.Worker
  alias CanonicalTailwind.Config

  def canonicalize(class_string, opts) do
    hash = route(opts)
    call(hash, class_string, _retry? = true)
  end

  # The hot path: a raw {opts, env} term we've seen before maps straight to its
  # resolved config's hash, so steady-state formatting never re-resolves (a
  # shell-out) or re-acquires a cold-start lock. The alias is keyed by the
  # EXACT raw term, not a hash of it: two distinct raw terms can never collide on
  # this key, so trusting it here can't route a request to the wrong worker.
  defp route(opts) do
    tailwind_env = Application.get_all_env(:tailwind)
    alias_key = {Keyword.get(opts, :canonical_tailwind, []), tailwind_env}

    case :persistent_term.get({__MODULE__, :alias, alias_key}, :miss) do
      :miss -> resolve_and_start!(opts, tailwind_env, alias_key)
      hash -> hash
    end
  end

  defp resolve_and_start!(opts, tailwind_env, alias_key) do
    # Serialize concurrent first-callers for this raw term so only one resolves
    # (a shell-out) and starts its worker; the rest take the cached alias.
    lock = alias_lock(alias_key)
    :global.trans(lock, fn -> resolve_alias!(opts, tailwind_env, alias_key) end)
  end

  # `:global` grants a shared lock to identical requester IDs, so use the caller
  # pid as requester and a per-resource id.
  defp alias_lock(alias_key), do: {{__MODULE__, :resolve, alias_key}, self()}

  defp resolve_alias!(opts, tailwind_env, alias_key) do
    # Re-check inside the lock: a racing first-caller may have cached the alias
    # while we waited, in which case we take it rather than resolve again.
    case :persistent_term.get({__MODULE__, :alias, alias_key}, :miss) do
      :miss ->
        config = Config.resolve!(opts, tailwind_env)
        hash = :erlang.phash2(config)
        cold_start!(hash, config)
        :persistent_term.put({__MODULE__, :alias, alias_key}, hash)
        hash

      hash ->
        hash
    end
  end

  # Distinct raw terms can resolve to the same config, so guard that config's
  # worker with its own lock rather than the per-term one.
  defp cold_start!(hash, config) do
    lock = cold_start_lock(hash)
    :global.trans(lock, fn -> start_or_verify_worker!(hash, config) end)
  end

  defp cold_start_lock(hash), do: {{__MODULE__, :cold_start, hash}, self()}

  defp start_or_verify_worker!(hash, config) do
    case :persistent_term.get({__MODULE__, :config, hash}, :miss) do
      :miss ->
        # Stop any worker orphaned by a previous cold start that crashed before
        # writing the config term, so we start clean instead of adopting it.
        clear_stale_worker!(hash)
        # Write the config term before starting the worker so a registered worker
        # always has one. A crash in between leaves at most a config without a
        # worker, which `ensure_started!/1` lazily recovers.
        :persistent_term.put({__MODULE__, :config, hash}, config)
        start_worker!(hash, config)

      ^config ->
        :ok

      stored_config ->
        raise hash_collision_error(hash, stored_config, config)
    end
  end

  defp clear_stale_worker!(hash) do
    name = worker_name(hash)
    if pid = GenServer.whereis(name), do: GenServer.stop(pid)
  end

  defp hash_collision_error(hash, stored_config, config) do
    ArgumentError.exception(
      "two distinct canonical_tailwind configurations collided on the same hash (#{hash}).\n\n" <>
        "Existing config:\n#{inspect(stored_config, pretty: true)}\n\n" <>
        "New config:\n#{inspect(config, pretty: true)}\n\n" <>
        "This is extremely unlikely; please open an issue."
    )
  end

  # A worker that vanished around call time, never started (`:noproc`) or
  # self-stopped on idle CLI death between the start and the call, is a transient
  # miss: retry once on a fresh worker. Any other crash, or a second vanish on the
  # retry, surfaces as a readable error rather than an opaque `GenServer.call` exit.
  defp call(hash, class_string, retry?) do
    ensure_started!(hash)
    name = worker_name(hash)
    GenServer.call(name, {:canonicalize, class_string}, :infinity)
  catch
    :exit, {:noproc, {GenServer, :call, _}} when retry? ->
      call(hash, class_string, false)

    :exit, {{:shutdown, {:cli_exited, _}}, {GenServer, :call, _}} when retry? ->
      call(hash, class_string, false)

    :exit, {reason, {GenServer, :call, _}} ->
      raise worker_error(reason)
  end

  defp ensure_started!(hash) do
    name = worker_name(hash)

    if !GenServer.whereis(name) do
      config = :persistent_term.get({__MODULE__, :config, hash})
      start_worker!(hash, config)
    end
  end

  defp start_worker!(hash, config) do
    case start_worker(hash, config) do
      :ok -> :ok
      {:error, %{__exception__: true} = error} -> raise error
      {:error, error} -> raise "failed to start canonicalizer: #{inspect(error)}"
    end
  end

  defp start_worker(hash, config) do
    name = worker_name(hash)

    case GenServer.start(Worker, config, name: name) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, {error, _stacktrace}} -> {:error, error}
    end
  end

  # One atom per distinct resolved config (a handful at most), so the bounded
  # dynamic atoms are safe.
  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp worker_name(hash), do: Module.concat(Worker, Integer.to_string(hash))

  defp worker_error({%{__exception__: true} = exception, _stacktrace}), do: exception

  defp worker_error(reason) do
    RuntimeError.exception("the tailwindcss canonicalizer worker crashed: #{inspect(reason)}")
  end
end
