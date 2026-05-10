defmodule CanonicalTailwind.ConfigLSPTest do
  use ExUnit.Case, async: false

  alias CanonicalTailwind.Config

  @binary Tailwind.bin_path()
  @target Tailwind.configured_target()

  defmodule FakeProject do
    def project, do: [app: :canonical_tailwind_lsp_sim, version: "0.0.1"]
  end

  defmodule FakeUmbrella do
    def project,
      do: [app: :canonical_tailwind_umbrella_sim, version: "0.0.1", apps_path: "apps"]
  end

  describe "LSP fallback" do
    test "Expert-style: cwd anchors fallback when project stack is empty" do
      Mix.ProjectStack.on_clean_slate(fn ->
        with_env("MIX_BUILD_PATH", tmp_path("expert-isolated/test"), fn ->
          config = Config.resolve!([canonical_tailwind: []], tailwind_env())
          assert config.binary == @binary
        end)
      end)
    end

    test "ElixirLS-style: project_file anchors fallback when stack has poisoned build_path" do
      Mix.ProjectStack.post_config(build_path: tmp_path(".elixir_ls/build"))
      Mix.Project.push(FakeProject, fake_mix_exs())

      try do
        config = Config.resolve!([canonical_tailwind: []], tailwind_env())
        assert config.binary == @binary
      after
        Mix.Project.pop()
      end
    end

    test "checks cwd in addition to project_file root" do
      bogus_root = tmp_path("bogus-fake-project")
      Mix.ProjectStack.post_config(build_path: tmp_path("isolated/build"))
      Mix.Project.push(FakeProject, Path.join(bogus_root, "mix.exs"))

      try do
        config = Config.resolve!([canonical_tailwind: []], tailwind_env())
        assert config.binary == @binary
      after
        Mix.Project.pop()
      end
    end

    test "umbrella: parent_umbrella anchors when project_file points at child" do
      umbrella_root = File.cwd!()
      child_root = Path.join([umbrella_root, "apps", "fake_child"])

      Mix.ProjectStack.on_clean_slate(fn ->
        Mix.Project.push(FakeUmbrella, Path.join(umbrella_root, "mix.exs"))
        Mix.ProjectStack.post_config(build_path: tmp_path("isolated/build"))
        Mix.Project.push(FakeProject, Path.join(child_root, "mix.exs"))

        try do
          config = Config.resolve!([canonical_tailwind: []], tailwind_env())
          assert config.binary == @binary
        after
          Mix.Project.pop()
          Mix.Project.pop()
        end
      end)
    end

    test "with `:tailwind, :path` override missing, error blames the override" do
      with_app_env(:tailwind, :path, "/no/such/tailwindcss", fn ->
        assert_raise ArgumentError,
                     ~r|tailwindcss binary at /no/such/tailwindcss \(from `:tailwind, :path`\)|,
                     fn -> Config.resolve!([canonical_tailwind: []], tailwind_env()) end
      end)
    end

    test "all candidates miss: error lists every checked path" do
      tmp = tmp_path("missing")
      File.mkdir_p!(tmp)
      isolated = Path.join(tmp, "isolated/test")

      try do
        Mix.ProjectStack.on_clean_slate(fn ->
          File.cd!(tmp, fn ->
            with_env("MIX_BUILD_PATH", isolated, fn ->
              error =
                assert_raise ArgumentError, fn ->
                  Config.resolve!([canonical_tailwind: []], tailwind_env())
                end

              expected_primary = Path.join(Path.dirname(isolated), "tailwind-#{@target}")
              expected_fallback = Path.join([tmp, "_build", "tailwind-#{@target}"])

              assert error.message =~ expected_primary
              assert error.message =~ expected_fallback
              assert error.message =~ "Run `mix tailwind.install`"
            end)
          end)
        end)
      after
        File.rm_rf!(tmp)
      end
    end
  end

  defp tailwind_env do
    [default: [args: ~w(--input=test/fixtures/input.css --output=/dev/null), cd: File.cwd!()]]
  end

  defp tmp_path(suffix) do
    Path.join([System.tmp_dir!(), "ct-#{System.unique_integer([:positive])}", suffix])
  end

  defp fake_mix_exs, do: Path.expand("../../mix.exs", __DIR__)

  defp with_env(key, value, fun) do
    prev = System.get_env(key)
    System.put_env(key, value)

    try do
      fun.()
    after
      if prev, do: System.put_env(key, prev), else: System.delete_env(key)
    end
  end

  defp with_app_env(app, key, value, fun) do
    env = Application.get_all_env(app)
    prev_set? = Keyword.has_key?(env, key)
    prev = Application.get_env(app, key)
    Application.put_env(app, key, value)

    try do
      fun.()
    after
      if prev_set?,
        do: Application.put_env(app, key, prev),
        else: Application.delete_env(app, key)
    end
  end
end
