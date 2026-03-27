defmodule CanonicalTailwind.Config do
  @moduledoc false

  @default_pool_size 6
  @minimum_version Version.parse!("4.2.2")
  @non_profile_keys [:version, :version_check, :path, :target, :cacerts_path]

  @enforce_keys [:args, :binary, :cd, :pool_size]
  defstruct @enforce_keys

  def resolve!(formatter_opts, tailwind_env) do
    opts = Keyword.get(formatter_opts, :canonical_tailwind, [])
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    {binary, profile_config} = resolve_binary!(opts, tailwind_env)
    cd = resolve_cd!(opts, profile_config)
    binary = Path.expand(binary, cd)
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

    %__MODULE__{args: args, binary: binary, cd: cd, pool_size: pool_size}
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
    unless Code.ensure_loaded?(Tailwind) do
      raise "The :tailwind package is required but not available. " <>
              "Add {:tailwind, ...} to your deps, or set canonical_tailwind: [binary: ...] explicitly."
    end
  end

  defp resolve_bin_path! do
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

  defp profile_config!(opts, tailwind_env) do
    profile = detect_profile!(opts, tailwind_env)

    Keyword.get(tailwind_env, profile) ||
      raise ArgumentError, "unknown tailwind profile: #{inspect(profile)}"
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
        raise "No tailwind profiles found. Configure :tailwind in your config."

      [{name, _profile}] ->
        name

      profiles ->
        names = Keyword.keys(profiles)

        raise "Multiple tailwind profiles found: #{inspect(names)}. " <>
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

      raise "canonical_tailwind requires tailwindcss >= #{@minimum_version}, got #{version}.#{hint}"
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
end
