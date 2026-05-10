defmodule CanonicalTailwind.PoolHelpers do
  @moduledoc false

  @pool_keys [:ready, :counter, :size, :config, :fingerprint]

  def reset_pool! do
    Process.registered()
    |> Enum.filter(&canonicalizer_name?/1)
    |> Enum.each(&GenServer.stop/1)

    Enum.each(@pool_keys, &:persistent_term.erase({CanonicalTailwind.Pool, &1}))
  end

  defp canonicalizer_name?(name) do
    name
    |> Atom.to_string()
    |> String.match?(~r/^Elixir\.CanonicalTailwind\.Canonicalizer\.\d+$/)
  end
end
