# AGENTS

## Source Of Truth

- This repository ports Rust upstream behavior from `https://github.com/0xPlaygrounds/rig.git`.
- The pinned upstream checkout lives at `vendor/rig`.
- Current parity work targets the Rust crate at `vendor/rig/crates/rig-core`.
- The pinned upstream commit for this baseline is `f77a5819ec2a71e98583480a68a341f816a75c8a`.

## Required Workflow

1. Treat upstream Rust behavior, tests, and fixtures as normative.
2. Update `plans/inventory/rust_port_inventory.tsv` before or alongside implementation.
3. Keep `plans/inventory/rust_source_parity.tsv` and `plans/inventory/rust_test_parity.tsv`
   in sync with the pinned upstream source.
4. Preserve upstream semantics before introducing Crystal idioms.
5. Run `make format`, `make lint`, and `make test` before closing work.

## Parity Commands

```bash
./scripts/ensure_parity_plan.sh . vendor/rig/crates/rig-core rust auto 0
./scripts/verify_parity_adversarial.sh . vendor/rig/crates/rig-core rust 'crystal spec' 'cargo test -p rig-core'
```
