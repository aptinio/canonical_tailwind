defmodule CanonicalTailwind.Canonicalizer do
  @moduledoc false

  alias CanonicalTailwind.Canonicalizer.Worker
  alias CanonicalTailwind.Config

  @ready_key {__MODULE__, :ready}
  @config_key {__MODULE__, :config}
  @fingerprints_key {__MODULE__, :fingerprints}

  def canonicalize(class_string, opts) do
    ensure_ready!(opts)
    call(class_string, _retry? = true)
  end

  defp ensure_ready!(opts) do
    if :persistent_term.get(@ready_key, false) do
      validate_config!(opts)
    else
      start!(opts)
    end
  end

  defp start!(opts) do
    # Serialize concurrent cold starts so only the first starts a worker; the
    # rest block, then take the :ready branch.
    :global.trans(cold_start_lock(), fn ->
      if :persistent_term.get(@ready_key, false) do
        validate_config!(opts)
      else
        do_start!(opts)
      end
    end)
  end

  defp cold_start_lock do
    # `:global` allows shared locks for identical requester IDs, so use the
    # caller pid as requester and a stable resource id.
    {{__MODULE__, :cold_start}, self()}
  end

  defp validate_config!(opts) do
    tailwind_env = Application.get_all_env(:tailwind)
    fingerprint = config_fingerprint(opts, tailwind_env)
    fingerprints = :persistent_term.get(@fingerprints_key)

    if !MapSet.member?(fingerprints, fingerprint) do
      reconcile_config!(fingerprints, fingerprint, opts, tailwind_env)
    end
  end

  # A fingerprint miss means the raw opts/env differ, not necessarily the resolved
  # config: immaterial :tailwind keys (e.g. :version_check) perturb the fingerprint
  # but not the binary, args, or cd. Caching the also-valid fingerprint avoids
  # re-resolving (a shell-out) per attribute.
  defp reconcile_config!(fingerprints, fingerprint, opts, tailwind_env) do
    stored_config = :persistent_term.get(@config_key)
    new_config = Config.resolve!(opts, tailwind_env)

    if new_config == stored_config do
      :persistent_term.put(@fingerprints_key, MapSet.put(fingerprints, fingerprint))
    else
      raise ArgumentError,
            "different canonical_tailwind configuration detected after the CLI started.\n\n" <>
              "Previous config:\n#{inspect(stored_config, pretty: true)}\n\n" <>
              "New config:\n#{inspect(new_config, pretty: true)}\n\n" <>
              "A single mix format run shares one tailwindcss CLI, so every app it formats must " <>
              "use the same canonical_tailwind configuration. Run mix format in each app " <>
              "separately so each gets its own CLI, or open an issue if you need differing " <>
              "configurations in one run."
    end
  end

  defp do_start!(opts) do
    # Stop any worker orphaned by a previous cold start that crashed before
    # writing its persistent terms, so we start clean instead of adopting it.
    clear_stale_worker!()

    tailwind_env = Application.get_all_env(:tailwind)
    fingerprint = config_fingerprint(opts, tailwind_env)
    config = Config.resolve!(opts, tailwind_env)

    start_worker!(config)

    :persistent_term.put(@config_key, config)
    :persistent_term.put(@fingerprints_key, MapSet.new([fingerprint]))
    :persistent_term.put(@ready_key, true)
  end

  defp clear_stale_worker! do
    if pid = GenServer.whereis(Worker), do: GenServer.stop(pid)
  end

  defp config_fingerprint(formatter_opts, tailwind_env) do
    canonical_tailwind_opts = Keyword.get(formatter_opts, :canonical_tailwind, [])
    :erlang.phash2({canonical_tailwind_opts, tailwind_env})
  end

  # A worker that vanished around call time, never started (`:noproc`) or
  # self-stopped on idle CLI death between the start and the call, is a transient
  # miss: retry once on a fresh worker. Any other crash, or a second vanish on the
  # retry, surfaces as a readable error rather than an opaque `GenServer.call` exit.
  defp call(class_string, retry?) do
    ensure_started!()
    GenServer.call(Worker, {:canonicalize, class_string}, :infinity)
  catch
    :exit, {:noproc, {GenServer, :call, _}} when retry? ->
      call(class_string, false)

    :exit, {{:shutdown, {:cli_exited, _}}, {GenServer, :call, _}} when retry? ->
      call(class_string, false)

    :exit, {reason, {GenServer, :call, _}} ->
      raise worker_error(reason)
  end

  defp ensure_started! do
    if !GenServer.whereis(Worker) do
      config = :persistent_term.get(@config_key)
      start_worker!(config)
    end
  end

  defp start_worker!(config) do
    case start_worker(config) do
      :ok -> :ok
      {:error, %{__exception__: true} = error} -> raise error
      {:error, error} -> raise "failed to start canonicalizer: #{inspect(error)}"
    end
  end

  defp start_worker(config) do
    case GenServer.start(Worker, config, name: Worker) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, {error, _stacktrace}} -> {:error, error}
    end
  end

  defp worker_error({%{__exception__: true} = exception, _stacktrace}), do: exception

  defp worker_error(reason) do
    RuntimeError.exception("the tailwindcss canonicalizer worker crashed: #{inspect(reason)}")
  end
end
