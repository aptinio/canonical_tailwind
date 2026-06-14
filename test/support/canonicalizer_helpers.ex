defmodule CanonicalTailwind.CanonicalizerHelpers do
  @moduledoc false

  alias CanonicalTailwind.Canonicalizer
  alias CanonicalTailwind.Canonicalizer.Worker

  def erase_persistent_terms! do
    for {key, _value} <- :persistent_term.get(), canonicalizer_key?(key) do
      :persistent_term.erase(key)
    end
  end

  defp canonicalizer_key?({Canonicalizer, kind, _}) when kind in [:alias, :config], do: true
  defp canonicalizer_key?(_), do: false

  def reset! do
    Enum.each(running_workers(), &GenServer.stop/1)
    erase_persistent_terms!()
  end

  def running_workers do
    prefix = "#{Worker}."

    for name <- Process.registered(),
        string = "#{name}",
        String.starts_with?(string, prefix),
        pid = Process.whereis(name),
        do: pid
  end

  def stored_configs do
    for {{Canonicalizer, :config, _hash}, config} <- :persistent_term.get(), do: config
  end
end
