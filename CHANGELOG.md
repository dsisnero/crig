## v0.42.0 (2026-07-24)

### Added
- **GenericCompletionModel** — shared `send_completion_request`/`send_streaming_request` helper with telemetry span lifecycle; 12 OpenAI-compatible providers migrated (OpenRouter, Perplexity, Together, Groq, Hyperbolic, DeepSeek, HuggingFace, Mira, ZAI, XiaomiMimo, MiniMax, Moonshot)
- **`force_tool_first_turn` example** — demonstrates hook-based `ToolChoice::Required` patch gated on turn index vs the footgun of re-forcing every turn

### Changed
- **Telemetry** — `record_model_input`/`record_model_output` removed from `SpanCombinator`; `gen_ai.input.messages` no longer populated in `chat_span`; message-content span fields kept empty
- **Tool metadata API** — flattened: `ToolDyn#definition(prompt)` replaced with `ToolDyn#description` + `ToolDyn#parameters`; `Crig.tool_definition(tool)` helper uses registered name as source of truth; all tool implementations and examples updated
- **ChatGPT error handling** — non-2xx Responses API errors now use `from_http_response` instead of bare `provider_error`, preserving HTTP status and body via `provider_response_status()`/`provider_response_body()`
- **Pinned upstream** — bumped to `a551c4c5c5df5d26b07111c722cc26ffb2777561` (upstream `v0.40.0`)
- **Parity inventory** — `rust_source_parity.tsv` tracks 2,368 API items; `rust_test_parity.tsv` tracks 903 test equivalents

### Removed
- **Galadriel provider** — marked for removal (upstream `#695490d`); still present in crig pending final cleanup

## v0.41.0 (2026-07-12)

### Added
- **AgentRun JSON serialization** — `to_json`/`from_json` extended with `completion_calls`; full round-trip preserves `max_turns`, `chat_history`, and `completion_calls` (R10)
- **StreamedTurnAssembler** — sans-IO accumulator for streaming agent turns: text accumulation, reasoning delta assembly, tool call validation, canonical finish ordering (R8)
- **AgentRun streamed turn support** — `record_streamed_completion_call`, `streamed_turn` methods on AgentRun; direct transition to `ExecutingTools` or `Done` from streamed turn (R8)
- **`composes_native_output_with_tools?`** — trait method on `CompletionModel`; OpenAI and Anthropic override to `true` (R3, R4)
- **`from_http_response` across all 17 providers** — HTTP error paths now preserve `provider_response_status`/`provider_response_body` for inspection (R5)
- **DeepSeek thinking/tool_choice suppression** — `thinking_is_disabled?` and `deepseek_tool_choice` helpers suppress `Required`/`Specific` tool_choice when thinking mode active (R2)
- **OpenAIUsage completion_tokens_details** — `reasoning_tokens`, timing fields (`queue_time`, `prompt_time`, `completion_time`, `total_time`); `output_tokens` uses `completion_tokens` when available (R3)
- **Anthropic `coerce_tool_input`** — forces `tool_use.input` to a JSON object at the send boundary (R4)
- **Ollama `think` as optional** — `think` defaults to `nil` (model default), supports `"max"` level; reasoning preserved as `AssistantContent::Reasoning` (R5)

### Changed
- **PromptRequest.send() → AgentRunner delegation** — legacy hand-rolled agent loop replaced with `@runner.run(@prompt)` matching upstream pattern (R1)
- **Old PromptHook types removed** — `PromptHook`, `HookAction`, `ToolCallHookAction`, `InvalidToolCallResolution`, `PromptHookAdapter` all removed; `AgentHook` with single `on_event(ctx, event) -> Flow` is the only hook interface (R9)
- **Agent stores `AgentHook` array** — no more single `@hook : PromptHook?`; `AgentBuilder#hook()` accepts `AgentHook` directly (R9)
- **Streaming prompt_request uses `AgentHook`** — `execute_tool_call` dispatches `StepEvent` through all registered hooks (R8)
- **`http_client` retry cleanup** — removed `Constant`/`Never` retry policies and `with_retry_policy` factory matching upstream removal (R6)
- **`non_success_status`/`non_success_body`** — helpers on `HttpClient::Error` (R6)
- **ProviderResponseError helpers on all 7 error types** — `CompletionError`, `EmbeddingError`, `TranscriptionError`, `VerifyError`, `ImageGenerationError`, `AudioGenerationError` now include `ProviderResponseHelpers` with `from_http_response`/`from_provider_body` factories (R7)
- **`provider_response_body`/`status` return for HttpError variants** — matches upstream where both `HttpError` and `ProviderResponse` variants expose provider response info (R3)
- **Anthropic null citations handling** — explicit `"citations": null` from API `content_block_start` events deserializes as empty vec (R4)
- **All quality gates clean** — `crystal tool format`, `ameba`, and `crystal spec` pass cleanly

### Dependencies
- Updated upstream pinned commit to `06bc651f4c64d1673ba6af698f6c66602c5d313f` (upstream v0.39.0) — 51 commits on `port/rig-v0.39.0`

## v0.40.0 (2026-06-28)

### Added
- **Streamable HTTP MCP example + live integration test** — `examples/rmcp.cr` is re-enabled now that the `mcp` shard ships `MCP::Client::StreamableHttpClientTransport`.
- **`shard_issues/`** — downstream shard-gap tracking.

### Changed
- Bumped `mcp` dependency to **v0.5.6**.
- **Split `DemotingPolicyMemory` / `CompactingMemory` into `src/crig/memory/policies.cr`**.

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
