# Changelog

## v0.1.6 (2026-06-13)

### Bug fixes
  - [CanonicalTailwind.Canonicalizer] Detect tailwindcss CLI death immediately instead of waiting out the full `:timeout`, and name the `:timeout` option in the timeout error
  - [CanonicalTailwind.Pool] Surface a dead or crashed CLI worker as a clear error instead of an opaque `GenServer.call` exit
  - [CanonicalTailwind.Pool] Stop the config-drift check from raising on a `:tailwind` env change that resolves to the same configuration (e.g. an umbrella app carrying an immaterial key like `:version_check`)
  - [CanonicalTailwind.Config] Track tailwind 0.5.0's version-suffixed binary name in the `_build/` LSP fallback, restoring on-save formatting under Expert / ElixirLS
  - [CanonicalTailwind.Config] Detect the CLI version reliably by running with `NO_COLOR` and reading the full version token, so the minimum-version check is no longer silently skipped on colorized or pre-release banners
  - [CanonicalTailwind.Config] Harden tailwind profile resolution: ignore non-keyword `:tailwind` globals when auto-detecting, and raise a clear error when a configured `:profile` names a non-profile key like `:version` instead of crashing with an opaque `Keyword.get/3` error

### Enhancements
  - [CanonicalTailwind.Config] Support tailwind 0.5.0's per-profile `:version`: resolve the binary for the selected profile's pinned version
  - [CanonicalTailwind.Pool] Point the config-drift error at the per-app `mix format` workaround

## v0.1.5 (2026-05-10)

### Bug fixes
  - [CanonicalTailwind.Pool] Recover missing canonicalizer workers, restoring long-running LSP sessions after a worker crash
  - [CanonicalTailwind.Config] Locate tailwindcss binary under LSPs that isolate `_build/`, restoring on-save formatting under Expert and ElixirLS

### Enhancements
  - [CanonicalTailwind.Pool] Prevent mixed-config workers by serializing cold start and clearing stale workers from prior incomplete cold starts

### Potential breaking changes
  - [CanonicalTailwind.Pool] Raise on `canonical_tailwind` config drift after the pool has started — umbrella setups that previously formatted concurrently with different formatter opts will now get a loud error instead of silent stale-config behavior

## v0.1.4 (2026-04-01)

### Enhancements
  - Add configurable `:timeout` option for CLI response (default 30s) (#6)

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
