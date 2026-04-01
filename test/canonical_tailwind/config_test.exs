defmodule CanonicalTailwind.ConfigTest do
  use ExUnit.Case, async: true

  alias CanonicalTailwind.Config

  @binary Tailwind.bin_path()
  @relative_binary Path.relative_to(@binary, File.cwd!())
  @project_root File.cwd!()
  @input "test/fixtures/input.css"

  describe ":binary" do
    test "resolves with :cd and :input" do
      config = resolve!(binary: @binary, cd: @project_root, input: @input)

      assert config.binary == @binary
      assert config.cd == @project_root
      assert "--input=#{@input}" in config.args
    end

    test "resolves with :cd" do
      config = resolve!(binary: @binary, cd: @project_root)

      assert config.binary == @binary
      assert config.cd == @project_root
    end

    test "resolves with :input" do
      config = resolve!(binary: @binary, input: @input)

      assert config.binary == @binary
      assert config.cd == @project_root
      assert "--input=#{@input}" in config.args
    end

    test "resolves without :cd or :input" do
      config = resolve!(binary: @binary)

      assert config.binary == @binary
      assert config.cd == @project_root
    end

    test "when relative, resolves against :cd" do
      config = resolve!(binary: @relative_binary, cd: @project_root)

      assert config.binary == @binary
    end

    test "must meet minimum version" do
      assert_raise ArgumentError, ~r/requires tailwindcss >= 4\.2\.2/, fn ->
        resolve!(binary: Path.expand("../fixtures/tailwindcss-v4.2.1", __DIR__), cd: ".")
      end
    end

    test "must be executable" do
      assert_raise ArgumentError, ~r/does not exist or is not executable/, fn ->
        resolve!(binary: "/nonexistent/tailwindcss")
      end
    end
  end

  describe ":cd" do
    test "must be a directory" do
      assert_raise ArgumentError, ~r/is not a directory/, fn ->
        resolve!(binary: @binary, cd: "/nonexistent/path")
      end
    end
  end

  @profile_config [
    args: ~w(--input=test/fixtures/input.css --output=/dev/null),
    cd: File.cwd!()
  ]

  describe ":input" do
    test "when not specified, no --input is passed to the binary" do
      config = resolve_with_env([bare_profile: [args: []]], profile: :bare_profile)

      refute Enum.any?(config.args, &String.starts_with?(&1, "--input="))
    end
  end

  describe ":profile" do
    test "provides input and cd" do
      config = resolve_with_env([test_profile: @profile_config], profile: :test_profile)

      assert "--input=test/fixtures/input.css" in config.args
      assert config.cd == @project_root
    end

    test "when unset, auto-detects if only one is configured" do
      config = resolve_with_env(only_profile: @profile_config)

      assert config.cd == @project_root
    end

    test "when unset, requires at least one to be configured" do
      assert_raise ArgumentError, ~r/no tailwind profiles found/, fn ->
        Config.resolve!([], [])
      end
    end

    test "when unset, requires only one to be configured" do
      tailwind_env = [
        first: @profile_config,
        second: @profile_config
      ]

      assert_raise ArgumentError, ~r/multiple tailwind profiles found/, fn ->
        Config.resolve!([], tailwind_env)
      end
    end

    test "must match one of the config profiles" do
      assert_raise ArgumentError, ~r/unknown tailwind profile/, fn ->
        resolve_with_env([other: @profile_config], profile: :nonexistent)
      end
    end
  end

  describe ":pool_size" do
    test "must be a positive integer" do
      assert_raise ArgumentError, ~r/expected :pool_size to be a positive integer/, fn ->
        resolve!(binary: @binary, pool_size: 0)
      end

      assert_raise ArgumentError, ~r/expected :pool_size to be a positive integer/, fn ->
        resolve!(binary: @binary, pool_size: -1)
      end

      assert_raise ArgumentError, ~r/expected :pool_size to be a positive integer/, fn ->
        resolve!(binary: @binary, pool_size: 1.5)
      end
    end
  end

  describe ":timeout" do
    test "must be a positive integer" do
      assert_raise ArgumentError, ~r/expected :timeout to be a positive integer/, fn ->
        resolve!(binary: @binary, timeout: 0)
      end

      assert_raise ArgumentError, ~r/expected :timeout to be a positive integer/, fn ->
        resolve!(binary: @binary, timeout: -1)
      end

      assert_raise ArgumentError, ~r/expected :timeout to be a positive integer/, fn ->
        resolve!(binary: @binary, timeout: 1.5)
      end
    end
  end

  defp resolve!(opts) do
    Config.resolve!([canonical_tailwind: opts], [])
  end

  defp resolve_with_env(tailwind_env, opts \\ []) do
    Config.resolve!([canonical_tailwind: opts], tailwind_env)
  end
end
