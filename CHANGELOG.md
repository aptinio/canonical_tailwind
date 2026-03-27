# Changelog

## v0.1.3 (2026-03-28)

### Enhancements
  - Support attributes other than `class` via `attribute_formatters` (#4)
  - Validate `:binary`, `:cd`, and `:pool_size` config options at startup
  - Check minimum CLI version against the installed binary, not just the configured version

## v0.1.2 (2026-03-25)

### Bug fixes
  - Fix Node-based CLI support by setting OS working directory from `:cd`

## v0.1.1 (2026-03-23)

### Bug fixes
  - [CanonicalTailwind] Fix newlines in class strings breaking port line protocol

## v0.1.0 (2026-03-20)

Initial release.

- Canonicalize Tailwind CSS utility classes in HEEx templates (sort, normalize, collapse)
- Delegate to `tailwindcss canonicalize --stream` via Elixir ports
- Pool of CLI processes for parallel `mix format`
- Works with LSP formatters (Expert, ElixirLS)
- Configurable pool size, binary path, and tailwind profile
- Fall back to `_build` when `Tailwind.bin_path()` resolves to a nonexistent location (LSP compatibility)
