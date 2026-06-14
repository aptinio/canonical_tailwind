# CanonicalTailwind

[![CI](https://github.com/aptinio/canonical_tailwind/actions/workflows/ci.yml/badge.svg)](https://github.com/aptinio/canonical_tailwind/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/canonical_tailwind.svg)](https://hex.pm/packages/canonical_tailwind)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/canonical_tailwind/)

Canonicalizes Tailwind CSS utility classes in HEEx templates via
`mix format`.

Delegates to the `tailwindcss` CLI's `canonicalize --stream`
subcommand, which sorts classes, normalizes utilities to their
canonical form, and collapses duplicates. Powered by the same
[Tailwind CSS](https://tailwindcss.com) engine as the
[Prettier plugin](https://github.com/tailwindlabs/prettier-plugin-tailwindcss).

```diff
- mr-4 custom-btn flex ml-[1rem] flex
+ custom-btn mx-4 flex
```

Unknown classes are preserved and sorted to the front.

## Requirements

- Elixir ~> 1.18
- Phoenix LiveView ~> 1.1 (for `attribute_formatters` support)
- The `tailwindcss` CLI >= 4.2.2 (first version with `canonicalize`)

The `:tailwind` package's default CLI version may lag this
requirement. If startup reports an older Tailwind version, set
`config :tailwind, version: "4.2.2"` (or newer) and run
`mix tailwind.install`.

## Setup

Add `canonical_tailwind` to your dependencies:

```elixir
# mix.exs
defp deps do
  [
    {:canonical_tailwind, "~> 0.1.0", only: [:dev, :test], runtime: false}
  ]
end
```

Then in `.formatter.exs`, add `attribute_formatters` alongside your
existing HEEx formatter plugin:

```elixir
# .formatter.exs
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  attribute_formatters: %{class: CanonicalTailwind},
  # ...
]
```

Now `mix format` automatically canonicalizes Tailwind classes in
`class` attributes, processing only files changed since its last run.

## Editor usage

If your editor formats via an LSP (like Expert or ElixirLS), the first
format-on-save after starting the editor will take a few seconds while
the `tailwindcss` CLI starts up. Subsequent saves are near instant.

## Configuration

If you have the [`:tailwind`](https://hex.pm/packages/tailwind) hex
package set up with a single profile (the default for Phoenix
projects), everything is detected automatically — no configuration
needed.

### Multiple tailwind profiles

If your project has multiple tailwind profiles, specify which one to
use:

```elixir
# .formatter.exs
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  attribute_formatters: %{class: CanonicalTailwind},
  canonical_tailwind: [profile: :app],
  # ...
]
```

### Timeout

The `tailwindcss` CLI needs to initialize before it can respond to
its first request. On slower CI machines or larger projects, this can
exceed the default timeout of 30 seconds. Adjust with `:timeout`:

```elixir
# .formatter.exs
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  attribute_formatters: %{class: CanonicalTailwind},
  canonical_tailwind: [timeout: 60_000],
]
```

### Custom binary

If you're not using the `:tailwind` hex package, provide the path to
the CLI binary and optionally a CSS entrypoint. The CLI needs your
CSS entrypoint to resolve `@theme` customizations and plugins when
determining canonical forms.

- **`:binary`** — path to the `tailwindcss` executable, relative to
  `:cd`
- **`:cd`** — working directory for the CLI process (defaults to the
  project root)
- **`:input`** — CSS entrypoint, relative to `:cd`

```elixir
# .formatter.exs
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  attribute_formatters: %{class: CanonicalTailwind},
  canonical_tailwind: [
    binary: "node_modules/.bin/tailwindcss",
    input: "css/app.css",
    cd: Path.expand("assets", __DIR__)
  ],
  # ...
]
```

### Other attributes

The `attribute_formatters` key maps attribute names to formatters, so
any attribute holding Tailwind classes can be canonicalized. Register
each one the same way as `class`:

```elixir
# .formatter.exs
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  attribute_formatters: %{class: CanonicalTailwind, "data-class": CanonicalTailwind},
  # ...
]
```

### Multiple builds in one run

A single `mix format` can span apps or directories that resolve to
different configurations: an umbrella whose apps use different tailwind
profiles, or a project using `subdirectories` with per-directory
`.formatter.exs` files. Each distinct configuration gets its own warm
`tailwindcss` CLI, so they coexist in one run without conflicting.

## Background

Built by a contributor to
[TailwindFormatter](https://github.com/100phlecs/tailwind_formatter/commits?author=aptinio),
[`attribute_formatters`](https://github.com/phoenixframework/phoenix_live_view/pull/3781),
and
[`canonicalize --stream`](https://github.com/tailwindlabs/tailwindcss/pull/19796).
