defmodule CanonicalTailwind.Pool do
  @moduledoc false

  @default_pool_size 6
  @ready_key {__MODULE__, :ready}
  @counter_key {__MODULE__, :counter}
  @size_key {__MODULE__, :size}

  def canonicalize(class_string, opts) do
    server = get_or_start_pool(opts)
    GenServer.call(server, {:canonicalize, class_string}, :infinity)
  end

  defp get_or_start_pool(opts) do
    if :persistent_term.get(@ready_key, false) do
      pick_server()
    else
      start_pool!(opts)
    end
  end

  defp start_pool!(opts) do
    pool_size = pool_size(opts)

    results =
      0..(pool_size - 1)
      |> Task.async_stream(
        fn i ->
          name = server_name(i)

          case GenServer.start(CanonicalTailwind.Canonicalizer, opts, name: name) do
            {:ok, _pid} -> :ok
            {:error, {:already_started, _pid}} -> :ok
            {:error, {error, _stacktrace}} -> {:error, error}
          end
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
        unless :persistent_term.get(@ready_key, false) do
          counter = :atomics.new(1, signed: false)
          :persistent_term.put(@counter_key, counter)
          :persistent_term.put(@size_key, pool_size)
          :persistent_term.put(@ready_key, true)
        end

        pick_server()

      %{__exception__: true} = error ->
        stop_all(pool_size)
        raise error

      error ->
        stop_all(pool_size)
        raise "failed to start canonicalizer pool: #{inspect(error)}"
    end
  end

  defp pick_server do
    pool_size = :persistent_term.get(@size_key)
    counter = :persistent_term.get(@counter_key)
    index = :atomics.add_get(counter, 1, 1)
    server_name(rem(index, pool_size))
  end

  defp server_name(index) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(CanonicalTailwind.Canonicalizer, "#{index}")
  end

  defp pool_size(opts) do
    opts
    |> Keyword.get(:canonical_tailwind, [])
    |> Keyword.get(:pool_size, @default_pool_size)
  end

  defp stop_all(pool_size) do
    for i <- 0..(pool_size - 1) do
      name = server_name(i)
      if pid = GenServer.whereis(name), do: GenServer.stop(pid)
    end
  end
end
