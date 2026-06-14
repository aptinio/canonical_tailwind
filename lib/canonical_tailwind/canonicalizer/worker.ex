defmodule CanonicalTailwind.Canonicalizer.Worker do
  @moduledoc false

  use GenServer

  @impl GenServer
  def init(config) do
    port = open_port(config)
    {:ok, %{port: port, timeout: config.timeout}}
  end

  defp open_port(config) do
    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      {:line, 65_536},
      {:cd, to_charlist(config.cd)},
      args: config.args
    ]

    Port.open({:spawn_executable, config.binary}, port_opts)
  end

  @impl GenServer
  def handle_call({:canonicalize, class_string}, _from, state) do
    Port.command(state.port, [class_string, ?\n])
    result = receive_line(state.port, state.timeout)
    {:reply, result, state}
  end

  defp receive_line(port, timeout) do
    receive_line(port, [], timeout)
  end

  defp receive_line(port, acc, timeout) do
    receive do
      {^port, {:data, {:eol, data}}} ->
        [data | acc]
        |> Enum.reverse()
        |> IO.iodata_to_binary()

      {^port, {:data, {:noeol, data}}} ->
        receive_line(port, [data | acc], timeout)

      {^port, {:exit_status, status}} ->
        raise "tailwindcss CLI exited (status #{status}) before responding"
    after
      timeout ->
        raise "tailwindcss CLI did not respond within #{timeout}ms. " <>
                "Increase the limit with `canonical_tailwind: [timeout: ...]` " <>
                "in your formatter options if this is a slow environment."
    end
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
