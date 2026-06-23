# AGENTS

## Source Of Truth

- This repository ports Rust upstream behavior from `https://github.com/0xPlaygrounds/rig.git`.
- The pinned upstream checkout lives at `vendor/rig`.
- Current parity work targets the Rust crate at `vendor/rig/crates/rig-core`.
- The pinned upstream commit for this baseline is `536c44f9f3ef8cac10ead3535528c7ceab3497f9`.

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

## Release Process

Versions are tracked via annotated git tags and `CHANGELOG.md`. On each release:

1. Add a `## vX.Y.Z (date)` entry to the top of `CHANGELOG.md` with `### Added/Changed/Fixed`.
2. Bump the `version:` field in `shard.yml` to match the release version `X.Y.Z`.
3. Commit (e.g. `deps:`/`chore:` for code, `docs: CHANGELOG vX.Y.Z`).
4. Create an annotated tag: `git tag -a vX.Y.Z -m "vX.Y.Z: <summary>"`.
5. Push the branch and the tag: `git push origin main && git push origin vX.Y.Z`.
