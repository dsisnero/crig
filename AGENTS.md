# AGENTS

## Source Of Truth

- This repository ports Rust upstream behavior from `https://github.com/0xPlaygrounds/rig.git`.
- The pinned upstream checkout lives at `vendor/rig`.
- Current parity work targets the Rust crate at `vendor/rig/rig/rig-core`.
- The pinned upstream commit for this baseline is `013d65a3f5d0a3cbf5a712826c343a3526d13112`.

## Required Workflow

1. Treat upstream Rust behavior, tests, and fixtures as normative.
2. Update `plans/inventory/rust_port_inventory.tsv` before or alongside implementation.
3. Keep `plans/inventory/rust_source_parity.tsv` and `plans/inventory/rust_test_parity.tsv`
   in sync with the pinned upstream source.
4. Preserve upstream semantics before introducing Crystal idioms.
5. Run `make format`, `make lint`, and `make test` before closing work.

## Parity Commands

```bash
./scripts/ensure_parity_plan.sh . vendor/rig/rig/rig-core rust auto 0
./scripts/verify_parity_adversarial.sh . vendor/rig/rig/rig-core rust 'crystal spec' 'cargo test -p rig-core'
```
