import Config

if config_env() == :test do
  # Defaults to the supported floor; CI overrides it to also test the latest CLI.
  config :tailwind, version: System.get_env("TAILWIND_VERSION", "4.2.2")
end
