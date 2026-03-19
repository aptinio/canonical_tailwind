import Config

if config_env() == :test do
  config :tailwind, version: "4.2.2"
end
