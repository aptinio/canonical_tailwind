defmodule CanonicalTailwind.CanonicalizerHelpers do
  @moduledoc false

  alias CanonicalTailwind.Canonicalizer.Worker

  @keys [:ready, :config, :fingerprints]

  def reset! do
    if pid = GenServer.whereis(Worker), do: GenServer.stop(pid)

    Enum.each(@keys, &:persistent_term.erase({CanonicalTailwind.Canonicalizer, &1}))
  end
end
