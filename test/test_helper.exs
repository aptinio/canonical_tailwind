Application.put_env(:tailwind, :canonical_tailwind,
  args: ~w(--input=test/fixtures/input.css),
  cd: Path.expand("..", __DIR__)
)

unless File.exists?(Tailwind.bin_path()), do: Tailwind.install()
ExUnit.start()
