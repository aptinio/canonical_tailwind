defmodule CanonicalTailwind.Canonicalizer.WorkerTest do
  use ExUnit.Case, async: true

  alias CanonicalTailwind.Canonicalizer.Worker
  alias CanonicalTailwind.Config

  test "returns the response when the CLI replies and then exits" do
    pid = start_worker!("tailwindcss-replies-then-exits", timeout: 30_000)
    ref = Process.monitor(pid)

    # The response line is consumed before the trailing exit status, so the call
    # succeeds; the queued exit then stops the worker for the next call to replace.
    assert GenServer.call(pid, {:canonicalize, "p-0 flex"}) == "flex p-0"
    assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:cli_exited, 0}}}, 2_000
  end

  @tag capture_log: true
  test "raises a clear timeout error naming the :timeout option when the CLI never replies" do
    pid = start_worker!("tailwindcss-never-replies", timeout: 50)

    assert {{%RuntimeError{message: message}, _stacktrace}, {GenServer, :call, _}} =
             catch_exit(GenServer.call(pid, {:canonicalize, "p-0 flex"}))

    assert message =~ "did not respond within 50ms"
    assert message =~ "canonical_tailwind: [timeout:"
  end

  @tag capture_log: true
  test "raises a clear error when the CLI process exits mid-request" do
    pid = start_worker!("tailwindcss-dies-mid-request", timeout: 30_000)

    assert {{%RuntimeError{message: message}, _stacktrace}, {GenServer, :call, _}} =
             catch_exit(GenServer.call(pid, {:canonicalize, "p-0 flex"}))

    assert message =~ "exited"
    assert message =~ "before responding"
  end

  test "stops itself when the CLI process exits while idle" do
    pid = start_worker!("tailwindcss-exits-idle", timeout: 30_000)
    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:cli_exited, 0}}}, 2_000
  end

  defp start_worker!(fixture, opts) do
    config = %Config{
      args: ["canonicalize", "--stream"],
      binary: Path.expand("../../fixtures/#{fixture}", __DIR__),
      cd: File.cwd!(),
      timeout: Keyword.fetch!(opts, :timeout)
    }

    {:ok, pid} = GenServer.start(Worker, config)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end
end
