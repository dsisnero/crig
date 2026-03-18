# crig

This repository is a Crystal port of https://github.com/0xPlaygrounds/rig.git.

Current upstream parity source:
- Repository: https://github.com/0xPlaygrounds/rig.git
- Submodule path: `vendor/rig`
- Rust crate under port: `vendor/rig/rig/rig-core`
- Pinned upstream commit: `f5c4812de02e776d9a68b481a8cf71ed6b572a2d`

`crig` is the Crystal workspace for a behavior-faithful port of Rig's Rust `rig-core`
crate. Upstream behavior, tests, and fixtures are the source of truth.

## Status

The repository is bootstrapped for parity work. Inventory manifests live under
`plans/inventory/`, and the initial Crystal surface is intentionally minimal while
the Rust API is translated in tracked slices.

## Installation

This shard is not feature-complete yet. Until the port reaches a stable API, consume
it from a local checkout rather than from a published shard.

## Usage

```crystal
require "crig"

Crig::VERSION
Crig::UPSTREAM_COMMIT
```

## Development

Install dependencies and use the standard quality gates:

```bash
make install
make format
make lint
make test
```

Canonical parity bootstrap/check commands:

```bash
./scripts/ensure_parity_plan.sh . vendor/rig/rig/rig-core rust auto 0
./scripts/check_port_inventory.sh . plans/inventory/rust_port_inventory.tsv vendor/rig/rig/rig-core rust
./scripts/check_source_parity.sh . plans/inventory/rust_source_parity.tsv vendor/rig/rig/rig-core rust
./scripts/check_test_parity.sh . plans/inventory/rust_test_parity.tsv vendor/rig/rig/rig-core rust
```

## Upstream README Highlights

This section merges key upstream README context rather than copying the submodule README
verbatim.

- Rig is a Rust library for building modular LLM-powered applications.
- The upstream `rig-core` crate exposes agent, completion, embedding, provider, tool,
  and vector-store abstractions.
- The upstream project supports many providers and companion integration crates, but this
  Crystal port will bring that surface over incrementally with parity tracking.
- Examples and usage context live in the upstream submodule README and examples under
  `vendor/rig/rig/rig-core/examples`.

For upstream README details, inspect the submodule README in `vendor/rig/README.md`.

## Contributing

Follow the source-of-truth workflow documented in `AGENTS.md` and `docs/`. Do not
implement behavior without updating the parity inventory first.
