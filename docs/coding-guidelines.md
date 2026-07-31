# Coding Guidelines

Preserve upstream behavior first. Keep naming drift explicit in the parity inventory,
use exact numeric widths when semantics depend on them, and avoid replacing upstream
behavior with more idiomatic Crystal behavior unless the deviation is documented.

## File Organization

Follow Ruby/Crystal file naming conventions: one class/struct/enum per file, with a
snake_case filename matching the primary type (e.g. `class CompletionRequest` lives in
`completion_request.cr`). Do not add new top-level types to a file that already defines
multiple types, and prefer splitting existing monolith files (keeping tests green after
each move) over appending to them. Specs mirror source paths one level deep:
`src/crig/foo/bar.cr` -> `spec/crig/foo/bar_spec.cr`.
