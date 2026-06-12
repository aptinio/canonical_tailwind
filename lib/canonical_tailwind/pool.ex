defmodule CanonicalTailwind.Pool do
  @moduledoc false

  @ready_key {__MODULE__, :ready}
  @counter_key {__MODULE__, :counter}
  @size_key {__MODULE__, :size}
  @config_key {__MODULE__, :config}
  @fingerprint_key {__MODULE__, :fingerprint}

  def canonicalize(class_string, opts) do
    server = get_or_start_pool(opts)
    call(server, class_string, _retry? = true)
  end

  defp get_or_start_pool(opts) do
    if :persistent_term.get(@ready_key, false) do
      validate_config_and_pick!(opts)
    else
      start_pool!(opts)
    end
  end

  defp start_pool!(opts) do
    # Serializes cold starts so workers cannot be registered with mixed configs.
    :global.trans(cold_start_lock(), fn ->
      if :persistent_term.get(@ready_key, false) do
        validate_config_and_pick!(opts)
      else
        do_start_pool!(opts)
      end
    end)
  end

  defp cold_start_lock do
    # `:global` allows shared locks for identical requester IDs, so use the
    # caller pid as requester and a stable resource id for the pool.
    {{__MODULE__, :cold_start}, self()}
  end

  defp validate_config_and_pick!(opts) do
    tailwind_env = Application.get_all_env(:tailwind)
    fingerprint = config_fingerprint(opts, tailwind_env)
    validate_config_fingerprint!(fingerprint, opts, tailwind_env)
    pick_server()
  end

  defp validate_config_fingerprint!(fingerprint, opts, tailwind_env) do
    stored_fingerprint = :persistent_term.get(@fingerprint_key, nil)

    if stored_fingerprint != fingerprint do
      previous_config = :persistent_term.get(@config_key)
      new_config = CanonicalTailwind.Config.resolve!(opts, tailwind_env)

      raise ArgumentError,
            "different canonical_tailwind configuration detected after the pool started.\n\n" <>
              "Previous config:\n#{inspect(previous_config, pretty: true)}\n\n" <>
              "New config:\n#{inspect(new_config, pretty: true)}\n\n" <>
              "A single mix format run shares one CLI pool, so every app it formats must use " <>
              "the same canonical_tailwind configuration. Run mix format in each app separately " <>
              "so each gets its own pool, or open an issue if you need differing configurations " <>
              "in one run."
    end
  end

  defp do_start_pool!(opts) do
    # Stop workers left over from a previous cold start that crashed before
    # writing persistent terms — otherwise they'd survive into the new pool
    # with stale config.
    clear_stale_workers!()

    tailwind_env = Application.get_all_env(:tailwind)
    fingerprint = config_fingerprint(opts, tailwind_env)
    config = CanonicalTailwind.Config.resolve!(opts, tailwind_env)
    pool_size = config.pool_size

    results =
      0..(pool_size - 1)
      |> Task.async_stream(
        fn i ->
          name = server_name(i)
          start_server(name, config)
        end,
        timeout: :infinity
      )
      |> Enum.to_list()

    case Enum.find_value(results, fn
           {:ok, {:error, error}} -> error
           {:exit, {error, _}} -> error
           _ -> nil
         end) do
      nil ->
        counter = :atomics.new(1, signed: false)
        :persistent_term.put(@config_key, config)
        :persistent_term.put(@fingerprint_key, fingerprint)
        :persistent_term.put(@counter_key, counter)
        :persistent_term.put(@size_key, pool_size)
        :persistent_term.put(@ready_key, true)

        pick_server()

      %{__exception__: true} = error ->
        stop_all(pool_size)
        raise error

      error ->
        stop_all(pool_size)
        raise "failed to start canonicalizer pool: #{inspect(error)}"
    end
  end

  defp clear_stale_workers! do
    Process.registered()
    |> Enum.filter(&canonicalizer_name?/1)
    |> Enum.each(&GenServer.stop/1)
  end

  defp canonicalizer_name?(name) do
    name
    |> Atom.to_string()
    |> String.match?(~r/^Elixir\.CanonicalTailwind\.Canonicalizer\.\d+$/)
  end

  defp config_fingerprint(formatter_opts, tailwind_env) do
    canonical_tailwind_opts = Keyword.get(formatter_opts, :canonical_tailwind, [])
    :erlang.phash2({canonical_tailwind_opts, tailwind_env})
  end

  defp stop_all(pool_size) do
    for i <- 0..(pool_size - 1) do
      name = server_name(i)
      if pid = GenServer.whereis(name), do: GenServer.stop(pid)
    end
  end

  # A worker that vanished around call time, never started (`:noproc`) or
  # self-stopped on idle CLI death between the pick and the call, is a transient
  # miss: retry once on a fresh worker. Any other crash, or a second vanish on the
  # retry, surfaces as a readable error rather than an opaque `GenServer.call` exit.
  defp call(server, class_string, retry?) do
    GenServer.call(server, {:canonicalize, class_string}, :infinity)
  catch
    :exit, {:noproc, {GenServer, :call, _}} when retry? ->
      call(pick_server(), class_string, false)

    :exit, {{:shutdown, {:cli_exited, _}}, {GenServer, :call, _}} when retry? ->
      call(pick_server(), class_string, false)

    :exit, {reason, {GenServer, :call, _}} ->
      raise worker_error(reason)
  end

  defp pick_server do
    pool_size = :persistent_term.get(@size_key)
    counter = :persistent_term.get(@counter_key)
    index = :atomics.add_get(counter, 1, 1)
    name = server_name(rem(index, pool_size))
    ensure_started(name)
    name
  end

  defp server_name(index) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(CanonicalTailwind.Canonicalizer, "#{index}")
  end

  defp ensure_started(name) do
    if !GenServer.whereis(name) do
      config = :persistent_term.get(@config_key)

      case start_server(name, config) do
        :ok -> :ok
        {:error, %{__exception__: true} = error} -> raise error
        {:error, error} -> raise "failed to start canonicalizer: #{inspect(error)}"
      end
    end
  end

  defp start_server(name, config) do
    case GenServer.start(CanonicalTailwind.Canonicalizer, config, name: name) do
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
