defmodule CanonicalTailwind.Canonicalizer do
  @moduledoc false

  use GenServer

  @impl GenServer
  def init(config) do
    port = open_port(config)
    {:ok, %{port: port, timeout: config.timeout}}
  end

  @impl GenServer
  def handle_call(
        {:canonicalize, class_string},
        _from,
        %{port: port, timeout: timeout} = state
      ) do
    Port.command(port, [class_string, ?\n])
    result = receive_line(port, timeout)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_info({port, {:data, _}}, %{port: port} = state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %{port: port}) do
    if Port.info(port), do: Port.close(port)
  end

  defp open_port(config) do
    port_opts = [
      :binary,
      :use_stdio,
      {:line, 65_536},
      {:cd, to_charlist(config.cd)},
      args: config.args
    ]

    Port.open({:spawn_executable, config.binary}, port_opts)
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
    after
      timeout ->
        raise "tailwindcss CLI did not respond within #{timeout}ms"
    end
  end
end
