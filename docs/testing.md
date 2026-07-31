# Testing

Port upstream tests as first-class work. `crystal spec` is the local gate, but parity
completion also requires the Rust source/test manifests and adversarial verification to
stay green against the pinned upstream checkout.

## Red-Green TDD

All porting work is test-driven: write a failing spec first, watch it fail, then make it
pass with the minimal change. Do not write implementation before its test.

## Spec Organization

Specs mirror source paths and stay small. Do not add `describe` blocks to a spec file
larger than a few hundred lines; split them into per-type spec files under `spec/crig/`
(e.g. `spec/crig/completion/completion_request_spec.cr`).
