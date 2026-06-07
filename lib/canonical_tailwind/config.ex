defmodule CanonicalTailwind.Config do
  @moduledoc false

  @compile {:no_warn_undefined, Tailwind}

  @default_pool_size 6
  @default_timeout 30_000
  @minimum_version Version.parse!("4.2.2")
  @non_profile_keys [:version, :version_check, :path, :target, :cacerts_path]

  @enforce_keys [:args, :binary, :cd, :pool_size, :timeout]
  defstruct @enforce_keys

  def resolve!(formatter_opts, tailwind_env) do
    opts = Keyword.get(formatter_opts, :canonical_tailwind, [])
    pool_size = validate_pool_size!(opts)
    timeout = validate_timeout!(opts)
    {binary, profile_config} = resolve_binary!(opts, tailwind_env)
    cd = resolve_cd!(opts, profile_config)
    validate_cd!(cd)
    binary = Path.expand(binary, cd)
    validate_binary!(binary)
    ensure_minimum_version!(binary, opts)

    args =
      Enum.reject(
        [
          "canonicalize",
          "--stream",
          resolve_input(opts, profile_config)
        ],
        &is_nil/1
      )

    %__MODULE__{
      args: args,
      binary: binary,
      cd: cd,
      pool_size: pool_size,
      timeout: timeout
    }
  end

  defp resolve_binary!(opts, tailwind_env) do
    case Keyword.get(opts, :binary) do
      nil ->
        ensure_tailwind!()
        binary = resolve_bin_path!()
        {binary, profile_config!(opts, tailwind_env)}

      path ->
        {path, []}
    end
  end

  defp ensure_tailwind! do
    if !Code.ensure_loaded?(Tailwind) do
      raise ArgumentError,
            "the :tailwind package is required but not available. " <>
              "Add {:tailwind, ...} to your deps, or set canonical_tailwind: [binary: ...] explicitly."
    end
  end

  defp resolve_bin_path! do
    primary = Tailwind.bin_path()
    override = Application.get_env(:tailwind, :path)

    cond do
      System.find_executable(primary) ->
        primary

      is_nil(override) ->
        candidates = fallback_bin_paths()

        Enum.find(candidates, &System.find_executable/1) ||
          raise ArgumentError, not_found_error(primary, candidates)

      true ->
        raise ArgumentError,
              "tailwindcss binary at #{primary} (from `:tailwind, :path`) does not exist or is not executable."
    end
  end

  # Recovers when an LSP isolates `_build/` and `Tailwind.bin_path/0` misses.
  defp fallback_bin_paths do
    name = "tailwind-#{Tailwind.configured_target()}"

    candidates =
      if Code.ensure_loaded?(Mix.Project) do
        [
          project_root(Mix.Project.parent_umbrella_project_file()),
          project_root(Mix.Project.project_file()),
          File.cwd!()
        ]
      else
        [File.cwd!()]
      end

    candidates
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
    |> Enum.map(&Path.join([&1, "_build", name]))
  end

  defp project_root(nil), do: nil
  defp project_root(file), do: Path.dirname(file)

  defp not_found_error(primary, candidates) do
    paths =
      [primary | candidates]
      |> Enum.uniq()
      |> Enum.map_join("\n  ", & &1)

    "tailwindcss binary not found. Checked:\n  #{paths}\n\n" <>
      "Run `mix tailwind.install`, or set `canonical_tailwind: [binary: ...]`."
  end

  defp profile_config!(opts, tailwind_env) do
    profile = detect_profile!(opts, tailwind_env)

    Keyword.get(tailwind_env, profile) ||
      raise ArgumentError, "unknown tailwind profile: #{inspect(profile)}."
  end

  defp detect_profile!(opts, tailwind_env) do
    case Keyword.get(opts, :profile) do
      nil -> detect_single_profile!(tailwind_env)
      name -> name
    end
  end

  defp detect_single_profile!(tailwind_env) do
    profiles =
      tailwind_env
      |> Keyword.drop(@non_profile_keys)
      |> Enum.reject(fn {_name, profile_config} -> profile_config == [] end)

    case profiles do
      [] ->
        raise ArgumentError, "no tailwind profiles found. Configure :tailwind in your config."

      [{name, _profile}] ->
        name

      profiles ->
        names = Keyword.keys(profiles)

        raise ArgumentError,
              "multiple tailwind profiles found: #{inspect(names)}. " <>
                "Set canonical_tailwind: [profile: :name] in your formatter options."
    end
  end

  defp resolve_cd!(opts, profile_config) do
    case Keyword.get(opts, :cd) do
      nil -> profile_config[:cd] || File.cwd!()
      path -> path
    end
  end

  defp ensure_minimum_version!(binary, opts) do
    version = detect_cli_version(binary)

    if version && Version.compare(version, @minimum_version) == :lt do
      hint =
        if not Keyword.has_key?(opts, :binary) do
          " Run `mix tailwind.install` to upgrade."
        end

      raise ArgumentError,
            "canonical_tailwind requires tailwindcss >= #{@minimum_version}, got #{version}.#{hint}"
    end
  end

  defp detect_cli_version(binary) do
    case System.cmd(binary, ["--help"], stderr_to_stdout: true, env: []) do
      {output, 0} ->
        case Regex.run(~r/tailwindcss v(\d+\.\d+\.\d+)/, output) do
          [_, version] -> Version.parse!(version)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp resolve_input(opts, profile_config) do
    case Keyword.get(opts, :input) do
      nil ->
        args = profile_config[:args] || []

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

  defp validate_pool_size!(opts) do
    size = Keyword.get(opts, :pool_size, @default_pool_size)

    if !(is_integer(size) and size > 0) do
      raise ArgumentError,
            "expected :pool_size to be a positive integer, got: #{inspect(size)}."
    end

    size
  end

  defp validate_timeout!(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    if !(is_integer(timeout) and timeout > 0) do
      raise ArgumentError,
            "expected :timeout to be a positive integer, got: #{inspect(timeout)}."
    end

    timeout
  end

  defp validate_cd!(cd) do
    if !File.dir?(cd) do
      raise ArgumentError, ":cd path #{inspect(cd)} is not a directory."
    end
  end

  defp validate_binary!(binary) do
    if !System.find_executable(binary) do
      raise ArgumentError,
            "tailwindcss binary at #{binary} does not exist or is not executable."
    end
  end
end
