defmodule CanonicalTailwind.Config do
  @moduledoc false

  @non_profile_keys [:version, :version_check, :path, :target, :cacerts_path]
  @minimum_version Version.parse!("4.2.2")

  defstruct [:binary, :cd, :args]

  def resolve!(formatter_opts, tailwind_env) do
    opts = Keyword.get(formatter_opts, :canonical_tailwind, [])
    {binary, profile_config} = resolve_binary(opts, tailwind_env)
    ensure_minimum_version!(binary, opts, tailwind_env)

    args =
      Enum.reject(
        [
          "canonicalize",
          "--stream",
          resolve_input(opts, profile_config),
          resolve_cwd(opts, profile_config)
        ],
        &is_nil/1
      )

    %__MODULE__{binary: binary, cd: nil, args: args}
  end

  defp resolve_binary(opts, tailwind_env) do
    case Keyword.get(opts, :binary) do
      nil ->
        ensure_tailwind!()
        binary = resolve_bin_path()
        {binary, profile_config(opts, tailwind_env)}

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

  defp profile_config(opts, tailwind_env) do
    profile = detect_profile(opts, tailwind_env)

    Keyword.get(tailwind_env, profile) ||
      raise ArgumentError, "unknown tailwind profile: #{inspect(profile)}"
  end

  defp detect_profile(opts, tailwind_env) do
    case Keyword.get(opts, :profile) do
      nil -> detect_single_profile(tailwind_env)
      name -> name
    end
  end

  defp detect_single_profile(tailwind_env) do
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

  defp ensure_minimum_version!(binary, opts, tailwind_env) do
    version =
      if Keyword.has_key?(opts, :binary) do
        detect_cli_version(binary)
      else
        Keyword.get(tailwind_env, :version)
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

  defp resolve_cwd(opts, profile_config) do
    case Keyword.get(opts, :cd) do
      nil ->
        case profile_config[:cd] do
          nil -> nil
          path -> "--cwd=" <> to_string(path)
        end

      path ->
        "--cwd=" <> to_string(path)
    end
  end
end
