defmodule CanonicalTailwind.Canonicalizer do
  use GenServer

  @non_profile_keys [:version, :version_check, :path, :target, :cacerts_path]
  @warm_up_classes "p-0 m-0 flex text-red-500 bg-white border rounded font-bold w-0 h-0"

  @init_timeout 30_000

  @impl GenServer
  def init(opts) do
    port = open_port(opts)
    Port.command(port, [@warm_up_classes, ?\n])
    receive_line(port, [], @init_timeout)
    {:ok, %{port: port}}
  end

  @impl GenServer
  def handle_call({:canonicalize, class_string}, _from, %{port: port} = state) do
    Port.command(port, [class_string, ?\n])
    result = receive_line(port)
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

  defp open_port(opts) do
    tw_opts = Keyword.get(opts, :canonical_tailwind, [])
    {binary, config} = resolve_binary(tw_opts)
    ensure_minimum_version!(binary, tw_opts)

    args =
      Enum.reject(
        [
          "canonicalize",
          "--stream",
          resolve_input(tw_opts, config),
          resolve_cwd(tw_opts, config)
        ],
        &is_nil/1
      )

    Port.open({:spawn_executable, binary}, [
      :binary,
      :use_stdio,
      {:line, 65_536},
      args: args
    ])
  end

  @minimum_version Version.parse!("4.2.2")

  defp ensure_minimum_version!(binary, tw_opts) do
    version =
      if Keyword.has_key?(tw_opts, :binary) do
        detect_cli_version(binary)
      else
        Application.get_env(:tailwind, :version)
      end

    parsed = version && Version.parse!(version)

    if parsed && Version.compare(parsed, @minimum_version) == :lt do
      raise "canonical_tailwind requires tailwindcss >= 4.2.2, got #{version}"
    end
  end

  defp detect_cli_version(binary) do
    case System.cmd(binary, ["--help"], stderr_to_stdout: true, env: []) do
      {output, 0} ->
        case Regex.run(~r/tailwindcss v(\d+\.\d+\.\d+)/, output) do
          [_, version] -> version
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp resolve_binary(tw_opts) do
    case Keyword.get(tw_opts, :binary) do
      nil ->
        ensure_tailwind!()
        binary = resolve_bin_path()
        {binary, profile_config(tw_opts)}

      path ->
        {path, []}
    end
  end

  defp resolve_bin_path do
    path = Tailwind.bin_path()

    if File.exists?(path) do
      path
    else
      name = Path.basename(path)
      fallback = Path.join("_build", name)

      if File.exists?(fallback) do
        Path.expand(fallback)
      else
        raise "tailwindcss binary not found at #{path} or #{fallback}. Run `mix tailwind.install`."
      end
    end
  end

  defp ensure_tailwind! do
    unless Code.ensure_loaded?(Tailwind) do
      raise "The :tailwind package is required but not available. " <>
              "Add {:tailwind, ...} to your deps, or set canonical_tailwind: [binary: ...] explicitly."
    end
  end

  defp profile_config(tw_opts) do
    profile = detect_profile(tw_opts)

    Application.get_env(:tailwind, profile) ||
      raise ArgumentError, "unknown tailwind profile: #{inspect(profile)}"
  end

  defp detect_profile(tw_opts) do
    case Keyword.get(tw_opts, :profile) do
      nil -> detect_single_profile()
      name -> name
    end
  end

  defp detect_single_profile do
    profiles =
      :tailwind
      |> Application.get_all_env()
      |> Keyword.drop(@non_profile_keys)
      |> Enum.reject(fn {_name, config} -> config == [] end)

    case profiles do
      [] ->
        raise "No tailwind profiles found. Configure :tailwind in your config."

      [{name, _profile}] ->
        name

      profiles ->
        names = Keyword.keys(profiles)

        raise "Multiple tailwind profiles found: #{inspect(names)}. " <>
                "Set canonical_tailwind: [profile: :name] in your formatter options."
    end
  end

  defp resolve_input(tw_opts, config) do
    case Keyword.get(tw_opts, :input) do
      nil ->
        args = config[:args] || []

        case Enum.find_value(args, &extract_input/1) do
          nil -> nil
          path -> "--input=" <> path
        end

      path ->
        "--input=" <> path
    end
  end

  defp extract_input("--input=" <> path), do: path
  defp extract_input(_), do: nil

  defp resolve_cwd(tw_opts, config) do
    case Keyword.get(tw_opts, :cd) do
      nil ->
        case config[:cd] do
          nil -> nil
          path -> "--cwd=" <> to_string(path)
        end

      path ->
        "--cwd=" <> to_string(path)
    end
  end

  @receive_timeout 10_000

  defp receive_line(port) do
    receive_line(port, [], @receive_timeout)
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
