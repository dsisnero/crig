# Architecture

`crig` is a Crystal porting workspace for Rig's Rust `rig-core` crate. The upstream
crate is vendored as a pinned git submodule under `vendor/rig`, and Crystal code is
expected to grow in parity-tracked slices rather than through untracked rewrites.
