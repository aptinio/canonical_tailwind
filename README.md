# CanonicalTailwind

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
`class` attributes.

## Editor usage

If your editor formats via an LSP (like Expert or ElixirLS), the first
format-on-save after starting the editor will take a few seconds while
the `tailwindcss` CLI processes start up. Subsequent saves are near
instant.

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

### Pool size

CanonicalTailwind runs a pool of `tailwindcss` CLI processes to
parallelize `mix format`. The default is 6. Smaller projects may
benefit from fewer (less startup cost), larger projects from more (up
to your CPU core count).

```elixir
# .formatter.exs
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  attribute_formatters: %{class: CanonicalTailwind},
  canonical_tailwind: [pool_size: 3],
]
```

### Without the tailwind hex package

If you're not using the `:tailwind` hex package, provide the binary
path and input CSS explicitly. The CLI needs your CSS entrypoint to
resolve `@theme` customizations and plugins when determining canonical
forms.

```elixir
# .formatter.exs
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  attribute_formatters: %{class: CanonicalTailwind},
  canonical_tailwind: [
    binary: "/path/to/tailwindcss",
    input: "assets/css/app.css"
  ],
  # ...
]
```

## Background

Built by a contributor to
[TailwindFormatter](https://github.com/100phlecs/tailwind_formatter/commits?author=aptinio),
[`attribute_formatters`](https://github.com/phoenixframework/phoenix_live_view/pull/3781),
and
[`canonicalize --stream`](https://github.com/tailwindlabs/tailwindcss/pull/19796).
