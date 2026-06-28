## v0.40.0 (2026-06-28)

### Added
- **Streamable HTTP MCP example + live integration test** — `examples/rmcp.cr` is re-enabled now that the `mcp` shard ships `MCP::Client::StreamableHttpClientTransport`. A new spec stands up `Crig::Examples::RMCP::StreamableServer` and drives a full round-trip (`list_tools` + `call_tool "sum"`) over streamable HTTP through the client transport.
- Re-enabled the `Crig::Examples::RMCP::StructRequest` spec and the `require "../examples/rmcp"` in the suite.
- **`shard_issues/`** — downstream shard-gap tracking. `shard_issues/mcp_1.md` documents the (now-resolved) missing `MCP::Client::StreamableHttpClientTransport`.

### Changed
- Bumped `mcp` dependency to **v0.5.6** — adds `MCP::Client::StreamableHttpClientTransport` (single-endpoint POST with `Mcp-Session-Id` session handling and JSON-response mode), enabling the streamable HTTP `rmcp` example.
- **Split `DemotingPolicyMemory` / `CompactingMemory` into `src/crig/memory/policies.cr`** to match the Rust upstream structure (core traits + `InMemoryConversationMemory` in `memory.cr`, policy adapters in `memory/policies.cr`).
- **All quality gates clean across `src`/`spec`** — `crystal tool format`, `ameba` (0 failures), and `crystal spec` (0 failures). Real naming/style fixes (`PredicateName`, `QueryBoolMethods`, `BlockParameterName`, `MultilineCurlyBlock`, `RescuedExceptionsVariableName`, dead-assignment removals, `RedundantWithIndex`) plus targeted `# ameba:disable` for telemetry accessor delegation, cyclomatic complexity, and deliberate `not_nil!` uses.

### Fixed
- `DemotingPolicyMemory` / `CompactingMemory` "tracks conversations" specs — corrected to trigger demotion (window of 1, two messages) so they exercise the real tracking contract (state is created on demotion/compaction), matching the characterization in `spec/memory_spec.cr`.

## v0.39.1 (2026-06-24)

### Added
- **`Crig::McpTool#call_async`** — non-blocking MCP tool call using `client.call_tool_async`, returns `Channel(MCP::Shared::AsyncResult(String))`; `call` delegates to `call_async` (sync contract preserved)
- **`Crig::VERSION` generated from `shard.yml`** — compile-time macro reads `shard.yml` version, single source of truth for releases
- **`InMemoryConversationMemory` uses `Sync::Map`** — replaced `Hash` + `Mutex` with `Sync::Map` for lock-free reads and atomic `compute`-based writes

### Changed
- Bumped `mcp` dependency from v0.3.0 to **v0.5.2** — `Sync::XMap` correlation maps, atomic request resolution, fiber-safe `Client`, router `Sync::XMap`
- **Removed `McpClientDispatcher`** — the per-client serializing actor is no longer needed; `mcp` 0.5.2 guarantees concurrent `call_tool` is fiber-safe with no external serialization

### Fixed
- `docs/pr-workflow.md` — expanded from 5 lines to concrete pre-commit checklist covering CHANGELOG, `shard.yml`, `src/crig.cr`, parity inventory, and quality gates
- `plans/inventory/rust_port_inventory.tsv` — removed stale "serialized shared-client dispatch" notes from `McpTool` and `rmcp_tool` entries

## v0.39.0 (2026-06-23)

### Added
- **Async prompt request APIs** — `send_async` on `PromptRequest`, `TypedPromptRequest`, and the streaming prompt request
  - returns `Channel(Crig::Concurrency::Result(T))`, matching existing `*_async` conventions (e.g. `list_models_async`)
  - keeps the synchronous `send` API intact while exposing native channel-based async boundaries
  - focused specs in `spec/prompt_request_async_spec.cr`

### Changed
- Bumped `mcp` dependency to **v0.3.0** — async tool handlers, concurrent request handling with inflight tracking, and request cancellation propagation

## v0.38.10 (2026-06-10)

### Fixed
- System role exhaustive cases in OpenRouter, Perplexity, OpenAI
- Tool validation skips when no static tools (runtime server compat)
- TypedPromptResponse deserialization fixture
- TemplateCompactor summary tests use System role
- json_schema spec field names match Calc tool

## v0.38.9 (2026-06-10)

### Fixed
- ToolChoice predicate methods (auto?, none?, required?, specific?)
- Content.to_json exhaustive case for server_tool_use / web_search_tool_result
- from_core_message System role handling in Cohere, DeepSeek, OpenAI
- Anthropic module method qualification

## v0.38.8 (2026-06-10)

### Changed
- Merged perf branch into main; all tags now on main
- Cleaned stray spec file

## v0.38.7 (2026-06-10)

### Changed
- **rig_tool** documented with examples, optional types spec
- README.md: new "Defining tools" section

## v0.38.6 (2026-06-10)

### Changed
- **rig_tool** uses json-schema shard for automatic schema generation
- Non-nilable fields auto-required, nilable fields optional
- Per-field descriptions via @[JSON::Field(description: ...)]

## v0.38.5 (2026-06-10)

### Changed
- Deep inventory sweep — deduplicated parity plan, all 2186 source API items tracked
- 28 spec files, 94 tests passing

## v0.38.4 (2026-06-10)

### Added
- **InvalidToolCallResolution** — non-streaming agent loop validates tools via hooks
  - Fail, Retry, Repair, Skip recovery actions wired into execute_tool_calls
  - resolve_invalid_tool_call orchestrates PromptHook callbacks

## v0.38.3 (2026-06-09)

### Added
- **OpenRouter ResponseImage replay avoidance** — filters tagged images in history

## v0.38.2 (2026-06-09)

### Added
- **Unreplayable reasoning detection** — responses_api iterates all content items, detects reasoning without IDs
- routes content as InputText vs OutputText based on replayability

### Fixed
- Plan checkboxes corrected after sed corruption

## v0.38.1 (2026-06-09)

### Fixed
- System role exhaustive case coverage in 5 provider files (Anthropic, Gemini, Mira, xAI)
- Anthropic System message splitting now matches upstream (hoisted for older models, preserved for Opus 4.8+)
- OpenAI Responses API resilience: tolerates missing assistant IDs, empty text, reasoning without ID
- OpenRouter Client.new overload ambiguity resolved with explicit BearerAuth wrapping

## v0.38.0 (2026-06-09)

### Added
- **Invalid Tool Call Recovery Hooks** — `InvalidToolCallContext`, `InvalidToolCallHookAction` (Fail/Retry/Repair/Skip), `on_invalid_tool_call` on `PromptHook`
- **Anthropic Mid-Conversation System Messages** — `Message::Role::System`, Opus 4.8+ support
- **OpenRouter Prompt Caching** — `apply_prompt_caching(body)` inserts cache_control on system message
- **Embeddings with Usage** — `EmbeddingResponse` struct, `embed_texts_with_usage` on `EmbeddingModel`
- **Tool Server append_toolset Visibility Fix** — appended tools now visible to `get_tool_definitions`
- **JSON Utils deserialize_json_string_or_value** — tolerates object-form streaming arguments
- **Gemini schema improvements** — `flatten_schema`, `resolve_refs`, `parse_ref_path` already ported
- **OpenAI Responses API resilience** — token details optional, missing ID tolerance

### Changed
- **Telemetry** — swapped `opentelemetry-api`/`opentelemetry-sdk` for `tracing.cr`
- **Text::additional_params** — `Text` struct gains `additional_params: JSON::Any?` for provider metadata
- **Anthropic Content** — `Citation` enum (6 variants), `ServerToolUse`, `WebSearchToolResult`, document fields
- **Anthropic streaming** — `ContentDelta::CitationsDelta` and `Unknown` variants
- **Streaming metadata** — `RawStreamingChoice::TextStart` and `TextAdditionalParams` variants
- **Text concatenation fix** — no `\n` insertion between text blocks
- **Null tool args normalization** — `null` falls back to `{}` for struct types
- **All 20 v0.37.0 features** — CompletionCall, Tool Validation, OpenRouter Enhancements, Gemini Tool Protocol, Anthropic Tool Cache Control, Agent hook, null_or_default

### Dependencies
- Added `dsisnero/tracing.cr` (~> 0.5)
- Dropped `wyhaines/opentelemetry-api.cr` and `wyhaines/opentelemetry-sdk.cr`
