## v0.39.1 (2026-07-31)

### Added
- **Doubleword provider** — OpenAI-compatible realtime tier (`src/crig/providers/doubleword/`): `client.cr`, `completion.cr`, `embedding.cr`, and model constants; registered in `DefaultProviders`. Completions reuse `OpenAI::Chat` types; embeddings route through the shared `EmbeddingCompatible` transport.
- **Shared embedding transport** — `EmbeddingCompatible` now surfaces provider-reported usage via `parse_response_with_usage` (with `requires_usage`/`MissingUsage` semantics), validates unsupported parameters (`encoding_format`/`user`), and accepts wire-level encoding strings; OpenRouter `EmbeddingModel` delegates to it so `embed_texts_with_usage` reports real usage.
- **Gemini image generation** — `src/crig/providers/gemini/image_generation.cr`: request body matches upstream (`responseModalities: ["IMAGE"]`, deep-merged `additional_params`), and non-success / 2xx error envelopes preserve status+body via `ImageGenerationError.from_http_response` (#2147).
- **`Agent#into_tool`** — upstream `Agent::into_tool -> DynamicTool` (agent name or `agent_tool` default), with inbound `ToolContext` propagation into the sub-agent (`ToolContext#inbound_only`, `AgentRunner#tool_context`, `PromptRequest#tool_context`); `AgentBuilder#tool(Agent)`/`tools(Array(Agent))` route through it.
- **`OneOrMany#from_iter_optional`** — returns `nil` for empty input, preserving first/rest split otherwise (upstream `from_iter_optional`).
- **`AgentRun` accessors** — `usage`, `is_done`, `response`, `cancel_error(reason)`, `pending_invalid_tool_call` (upstream `AgentRun`).
- **Streaming hook observations** — `StepEvent.text_delta`/`tool_call_delta` factories and `on_text_delta`/`on_tool_call_delta`/`on_stream_response_finish` hooks (backward-compatible via `on_observation`); `on_text_delta` dispatched in the streaming path.
- **Per-request builder overrides** — `preamble`, `temperature`, `max_tokens`, `tool_choice`, `additional_params` and their `without_*` clearing variants on `AgentRunner`, `PromptRequest`, and `TypedPromptRequest` (matching upstream `forward_prompt_setters!`).
- **MCP tool timeout** — `DEFAULT_MCP_TOOL_TIMEOUT = 300s`, `McpTool#with_timeout`, and a `select`+`timeout` race in `call_async` resolving to a `ToolError` on elapse instead of blocking forever (#1914).
- **`AgentRun` streamed turn support** — `record_streamed_completion_call`, `streamed_turn` on `AgentRun`; direct transition to `ExecutingTools` or `Done` from a streamed turn.
- **`composes_native_output_with_tools?`** — trait method on `CompletionModel`; OpenAI and Anthropic override to `true`.
- **`from_http_response` across all 17 providers** — HTTP error paths preserve `provider_response_status`/`provider_response_body` for inspection.
- **`force_tool_first_turn` example** — hook-based `ToolChoice::Required` patch gated on turn index.
- **`Crig::VERSION` generated from `shard.yml`** — compile-time macro reads `shard.yml` version as the single source of truth.

### Changed
- **Agent runner aligned with upstream v0.41.0** — removed deprecated `Agent#completion`/`Agent#stream_completion` and the Crystal-only `StreamingCompletion` trait; `Agent` keeps `StreamingPrompt`/`StreamingChat` only. `StreamingPromptRequest` builds via a documented `build_completion_request` helper. Seeded `Agent#static_context` into `AgentRunner` (static context previously never reached the runner path).
- **Spec organization** — split the monolithic `spec/crig_spec.cr` into ~45 per-type spec files mirroring `src/` paths; shared fakes consolidated into `spec/support/`. Full suite: 1403 examples, 0 failures (3 pre-existing pending).
- **Tool metadata API** — flattened: `ToolDyn#definition(prompt)` replaced with `ToolDyn#description` + `ToolDyn#parameters`; `Crig.tool_definition(tool)` uses the registered name as source of truth.
- **`DynamicTool` declares `include ToolDyn`** — `ToolSet#add_tool`/`ToolServer#tool` accept it directly.
- **`ToolServerHandle#execute`** — clears, dispatches, and publishes per-dispatch `ToolContext` result metadata (upstream `ToolServerHandle::execute`); `ToolServer#call_tool` accepts an optional context.
- **SSE retry cycle** — `GenericEventSource` starts a fresh retry cycle on mid-stream transport errors (upstream `SourceState::Open`), so `max_retries` isn't exhausted prematurely.
- **ChatGPT error handling** — non-2xx Responses API errors use `from_http_response` preserving HTTP status and body.
- **Old `PromptHook` types removed** — `PromptHook`, `HookAction`, `ToolCallHookAction`, `InvalidToolCallResolution`, `PromptHookAdapter`; `AgentHook` with `on_event(ctx, event) -> Flow` is the only hook interface.
- **`http_client` retry cleanup** — removed `Constant`/`Never` retry policies and `with_retry_policy` factory matching upstream removal.
- **ProviderResponseError helpers on all 7 error types** — `CompletionError`, `EmbeddingError`, `TranscriptionError`, `VerifyError`, `ImageGenerationError`, `AudioGenerationError` include `ProviderResponseHelpers`.
- **Telemetry** — `record_model_input`/`record_model_output` removed from `SpanCombinator`.
- **Extractor** — removed `ExtractorSubmitTool`; extraction routes through the runner's `output_tool` + `ignore_unhandled_invalid_tool_calls` mechanism.
- **Pinned upstream** — `a551c4c5c5df5d26b07111c722cc26ffb2777561` (upstream v0.40.0), targeting v0.41.0 parity.
- **Parity inventory** — `rust_source_parity.tsv` tracks 2,368 API items; `rust_test_parity.tsv` tracks 903 test equivalents.
- Bumped `mcp` dependency to **v0.5.6**.

### Removed
- **Galadriel provider** — marked for removal (upstream `#695490d`); still present pending final cleanup.
- **`McpClientDispatcher`** — no longer needed; `mcp` 0.5.2 guarantees fiber-safe concurrent `call_tool`.

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
