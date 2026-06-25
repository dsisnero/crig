# PR Workflow

Before opening or finishing a change:

1. Update docs to reflect the current codebase (no stale/generic content):
   - `CHANGELOG.md` — add `## vX.Y.Z (date)` at the top with `### Added/Changed/Fixed`
   - `README.md` — update feature table, examples, and file-map if APIs shifted
   - `docs/*.md` — keep architecture, coding-guidelines, testing, and pr-workflow accurate
   - `shard.yml` — bump `version:` for release commits (`Crig::VERSION` reads this at compile time via macro)
2. Update the parity ledger:
   - `plans/inventory/rust_port_inventory.tsv` — mark new ports, update stale notes about Crystal-only adapters (e.g. dispatcher removal)
   - `plans/inventory/rust_source_parity.tsv` — keep in sync with `vendor/rig`
   - `plans/inventory/rust_test_parity.tsv` — keep in sync with `vendor/rig`
3. Run quality gates:
   ```bash
   make format && make lint && make test
   ```
4. Commit with a semantic prefix: `feat:`, `fix:`, `deps:`, `chore:`, `docs:`.
5. Record any intentional upstream deviation in the parity inventory with a `crystal_idiom` or `crig_only` note.
