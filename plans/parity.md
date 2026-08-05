## Upstream Baseline

- **Repository**: `https://github.com/0xPlaygrounds/rig.git`
- **Crates**: `crates/rig-core` + `crates/rig-agent`
- **Pinned upstream**: `68b4eabb8c9cf749ca73c917b9306e97fb0eda24` (rig-core v0.41.0)
- **Crystal tag**: `v0.41.0` (feature plan complete; parity manifests regenerated)

## v0.41.0 Features (complete)

**Detailed plan**: [plans/v41.md](./v41.md)

Major refactor: rig-core split into rig-core (provider-agnostic contracts) + rig-agent (agent runtime).
Key findings from [release discussion #2225](https://github.com/0xPlaygrounds/rig/discussions/2225) and `MIGRATING.md`.

### Phase 0 — Silent behavior changes
- [x] max_turns counts exact model calls
- [x] Ollama max_tokens honored as num_predict
- [x] Multipart tool results reach providers intact
- [x] Extractor usage undercounting fix
- [x] Structured-output tools fail closed on name collision
- [x] WASM target-based — N/A (Crystal)

### Phase 1 — Foundation & inventory
- [x] UPSTREAM_COMMIT set to `68b4eabb8c9cf749ca73c917b9306e97fb0eda24`
- [x] UPSTREAM_SOURCE_PATH set for both rig-core and rig-agent
- [x] Parity inventory regenerated
- [x] MIGRATING.md annotated

### Phase 2 — Core contract changes
- [x] Non-exhaustive error types (all have `Other` wildcard variant)
- [x] Completion model/message/request updates
- [x] PortableTool, ToolOutput, simplified tool dispatch (single `call`, `ToolContext`, `DynamicTool`, `ToolSet::execute`)
- [x] Error consolidation (ToolExecutionError, ToolErrorKind, ToolResult)
- [x] HTTP client deduplication (generic via `Client(Ext, H)`)
- [x] Streaming core types match
- [x] Memory (ConversationMemory raises instead of Result)
- [x] WASM compat — N/A (Crystal)
- [x] Embeddings (Embed trait, EmbeddingCompatible module, Base64 rejection)
- [x] `json_utils` marked `@[Doc::Hidden]`
- [x] `provider_response` module marked `@[Doc::Hidden]`
- [ ] SSE helpers (227 vs 374 lines upstream)
- [ ] OneOrMany minor updates

### Phase 3 — Agent runtime alignment
- [x] Agent builder: `tools(Vec)` deprecated, `dynamic_context` preserved, provider-independent hooks
- [x] Agent's model is fixed and private (no per-call `.model()` setters)
- [x] AgentRun sans-I/O state machine preserved
- [x] Extractor routes through full hook lifecycle (via AgentRunner)
- [x] Event-specific hooks (CompletionCallAction, ToolCallAction, ToolResultAction, etc.)
- [x] Invalid-tool hooks return None to defer
- [ ] Response retry hooks (`on_retry`, #2182) — post-v0.41.0 feature
- [ ] Remove `agent.completion()` / `agent.stream_completion()` (deprecated)
- [ ] `CompletionResponseEvent` / `StreamResponseFinish` expose canonical Rig content
- [ ] Update prompt_request and streaming
- [ ] Update agent run (run.cr, run/streamed.cr)
- [ ] Update agent/completion.cr
- [ ] Update tool/rmcp.cr (213 vs 1,983 lines upstream)
- [ ] Update tool/server.cr (314 vs 1,246 lines upstream)

### Phase 4 — Provider updates
- [ ] Doubleword provider (new)
- [ ] Full GenericEmbeddingModel struct
- [ ] Anthropic code execution tool results
- [ ] Gemini image generation error handling
- [ ] MCP dependency updates

### Phase 5 — Telemetry
- [ ] Completion-parent contract (`completion_parent_span!` macro)
- [ ] Sensitive span content opt-in
- [ ] Centralize completion span lifecycle

### Phase 6 — Derive macros
- [x] `required-ness` follows parameter types
- [x] `Option` in explicit `required()` is compile error
- [x] Names in `params()`/`required()` must match actual parameters
- [x] Generated `parameters()` builds schema once (LazyLock)
- [x] Schema-type coverage specs
- [x] `Embed` derive emits fully qualified impls
- [x] Macro-generated code resolves through `Crig`
- [x] Wildcard context binding — N/A (Crystal)

### Phase 7 — Test & parity reconciliation
- [x] 50+ spec files added across modules
- [x] make format passes
- [x] make lint passes
- [x] make test passes (1641 examples, 0 failures, 0 errors, 3 pending)
- [x] Parity verification scripts run
- [x] Update rust_source_parity.tsv and rust_test_parity.tsv
- [x] Update plans/parity.md completion status

## v0.40.0 Features (completed)

**Detailed plan**: [plans/v40.md](./v40.md)

## v0.39.0 Features (previously completed)

**Detailed plan**: [plans/v39.md](./v39.md) — all 24 chunks completed (14 C + 10 R)

## Remaining Gaps

- `rust_source_parity.tsv` (1955 items) and `rust_test_parity.tsv` (839 items) are regenerated against the v0.41.0 layout as baseline manifests; per-item `mapped` status is filled in as the curated `rust_port_inventory.tsv` (2668 ported, 240 intentional divergences) is reconciled
- Upstream `rig-core` test parity not yet re-verified via `cargo test` side-by-side (adversarial harness available)

## Companion Crates Ported

| Crate | Status | Crystal Location |
|-------|--------|-----------------|
| `rig-memory` | ✅ Complete | `src/crig/memory.cr`, `src/crig/memory/policies.cr` |
| `rig-vectorize` | ✅ Complete | `src/crig/vector_store/vectorize.cr` |
| Others | ⬜ (separate repos) | — |
