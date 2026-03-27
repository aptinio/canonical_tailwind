defmodule CanonicalTailwind.ConfigTest do
  use ExUnit.Case, async: true

  alias CanonicalTailwind.Config

  @binary Tailwind.bin_path()
  @relative_binary Path.relative_to(@binary, File.cwd!())
  @project_root File.cwd!()
  @input "test/fixtures/input.css"

  describe "custom binary" do
    test "with :binary, :cd, and :input" do
      config = resolve!(binary: @binary, cd: @project_root, input: @input)

      assert config.binary == @binary
      assert config.cd == @project_root
      assert "--input=#{@input}" in config.args
    end

    test "with :binary and :cd" do
      config = resolve!(binary: @binary, cd: @project_root)

      assert config.binary == @binary
      assert config.cd == @project_root
    end

    test "with :binary and :input, cd defaults to project root" do
      config = resolve!(binary: @binary, input: @input)

      assert config.binary == @binary
      assert config.cd == @project_root
      assert "--input=#{@input}" in config.args
    end

    test "with :binary only, cd defaults to project root" do
      config = resolve!(binary: @binary)

      assert config.binary == @binary
      assert config.cd == @project_root
    end

    test "resolves relative :binary against :cd" do
      config = resolve!(binary: @relative_binary, cd: @project_root)

      assert config.binary == @binary
    end

    test "raises when explicit binary version is too old" do
      assert_raise ArgumentError, ~r/requires tailwindcss >= 4\.2\.2/, fn ->
        resolve!(binary: Path.expand("../fixtures/tailwindcss-v4.2.1", __DIR__), cd: ".")
      end
    end

    test "raises when binary is not executable" do
      assert_raise ArgumentError, ~r/does not exist or is not executable/, fn ->
        resolve!(binary: "/nonexistent/tailwindcss")
      end
    end
  end

  describe "cd" do
    test "raises when :cd is not a directory" do
      assert_raise ArgumentError, ~r/is not a directory/, fn ->
        resolve!(binary: @binary, cd: "/nonexistent/path")
      end
    end
  end

  describe "profile config" do
    @profile_config [
      args: ~w(--input=test/fixtures/input.css --output=/dev/null),
      cd: File.cwd!()
    ]

    test "resolves input and cd from profile" do
      config = resolve_with_env([test_profile: @profile_config], profile: :test_profile)

      assert "--input=test/fixtures/input.css" in config.args
      assert config.cd == @project_root
    end

    test "works without input or cd in profile" do
      config = resolve_with_env([bare_profile: [args: []]], profile: :bare_profile)

      assert config.cd == @project_root
      refute Enum.any?(config.args, &String.starts_with?(&1, "--input="))
    end

    test "raises when no tailwind profiles are configured" do
      assert_raise ArgumentError, ~r/no tailwind profiles found/, fn ->
        Config.resolve!([], [])
      end
    end

    test "raises when multiple tailwind profiles exist without explicit profile" do
      tailwind_env = [
        first: @profile_config,
        second: @profile_config
      ]

      assert_raise ArgumentError, ~r/multiple tailwind profiles found/, fn ->
        Config.resolve!([], tailwind_env)
      end
    end

    test "raises for unknown tailwind profile" do
      assert_raise ArgumentError, ~r/unknown tailwind profile/, fn ->
        resolve_with_env([other: @profile_config], profile: :nonexistent)
      end
    end

    defp resolve_with_env(tailwind_env, opts) do
      Config.resolve!([canonical_tailwind: opts], tailwind_env)
    end
  end

  describe "pool size" do
    test "raises when pool_size is not a positive integer" do
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

  defp resolve!(opts) do
    Config.resolve!([canonical_tailwind: opts], [])
  end
end
