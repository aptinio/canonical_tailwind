defmodule CanonicalTailwind.Canonicalizer.Worker do
  @moduledoc false

  use GenServer

  @impl GenServer
  def init(config) do
    port = open_port(config)
    {:ok, %{port: port, timeout: config.timeout, ready?: false}}
  end

  defp open_port(config) do
    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      {:line, 65_536},
      {:cd, to_charlist(config.cd)},
      {:env, env_charlists(config.env)},
      args: config.args
    ]

    Port.open({:spawn_executable, config.binary}, port_opts)
  end

  defp env_charlists(env) do
    Enum.map(env, fn
      {name, nil} -> {to_charlist(name), false}
      {name, value} -> {to_charlist(name), to_charlist(value)}
    end)
  end

  @impl GenServer
  def handle_call({:canonicalize, class_string}, _from, state) do
    deadline = System.monotonic_time(:millisecond) + state.timeout
    state = ensure_ready(state, deadline)
    Port.command(state.port, [class_string, ?\n])
    result = receive_line(state.port, [], state.timeout, deadline)
    {:reply, result, state}
  end

  defp ensure_ready(%{ready?: true} = state, _deadline), do: state

  defp ensure_ready(state, deadline) do
    # Unknown classes round-trip unchanged. Synchronize before sending user input
    # so plugin startup logs cannot be mistaken for a canonicalization response.
    marker = "canonical-tailwind-ready-#{System.unique_integer([:positive])}"
    Port.command(state.port, [marker, ?\n])
    await_ready(state.port, marker, state.timeout, deadline)
    %{state | ready?: true}
  end

  defp await_ready(port, marker, timeout, deadline) do
    case receive_line(port, [], timeout, deadline) do
      ^marker -> :ok
      _startup_output -> await_ready(port, marker, timeout, deadline)
    end
  end

  defp receive_line(port, acc, timeout, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    if remaining <= 0, do: raise_timeout(timeout)

    receive do
      {^port, {:data, {:eol, data}}} ->
        [data | acc]
        |> Enum.reverse()
        |> IO.iodata_to_binary()

      {^port, {:data, {:noeol, data}}} ->
        receive_line(port, [data | acc], timeout, deadline)

      {^port, {:exit_status, status}} ->
        raise "tailwindcss CLI exited (status #{status}) before responding"
    after
      remaining -> raise_timeout(timeout)
    end
  end

  defp raise_timeout(timeout) do
    raise "tailwindcss CLI did not respond within #{timeout}ms. " <>
            "Increase the limit with `canonical_tailwind: [timeout: ...]` " <>
            "in your formatter options if this is a slow environment."
  end

  @impl GenServer
  def handle_info({port, {:data, _}}, %{port: port} = state) do
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    {:stop, {:shutdown, {:cli_exited, status}}, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if Port.info(state.port), do: Port.close(state.port)
  end
end
