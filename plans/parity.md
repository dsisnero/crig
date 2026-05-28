## Upstream Baseline

- **Repository**: `https://github.com/0xPlaygrounds/rig.git`
- **Crates**: `crates/rig-core`
- **Pinned commit**: `f77a5819ec2a71e98583480a68a341f816a75c8a`
- **Latest upstream**: `a0cd8a8f505af70f10918e994bd45d8241ee4f37` (rig-core v0.37.0)
- **Commits behind**: 21 commits spanning v0.36.0 → v0.37.0

## v0.37.0 New Features (pending port)

These features exist in the latest upstream but not in the pinned baseline or the Crystal port.

### Feature Progress

- [x] **Text::additional_params & Citation Support**
  - Upstream: `src/completion/message.rs`, `src/streaming.rs`, `src/providers/anthropic/completion.rs`, `src/providers/anthropic/streaming.rs`
  - `Text` struct gains `additional_params: Option<JSON::Any>` for provider-specific metadata
  - `Text::new(text)` / `Text.from(text)` constructors with default nil additional_params
  - Custom JSON deserializer handles `additional_params` field
  - Note: Full Anthropic citations (Citation enum, server tool use, web search, document title/context) deferred to future PR

- [x] **tool_use_prompt_tokens on Usage**
  - Upstream: `src/completion/request.rs`, `src/telemetry/mod.rs`, all provider files
  - `Usage` gains `tool_use_prompt_tokens: UInt64` field (serde default)
  - `Usage::new()`, `Add`, `AddAssign` updated
  - `SpanCombinator::record_token_usage` records new field in traces
  - All providers (anthropic, gemini, openai, ollama, etc.) updated to map provider-specific field
  - Estimated: ~150 lines across 12+ files

- [x] **CompletionCall Tracking in Agent Responses**
  - Upstream: `src/agent/completion.rs`, `src/agent/prompt_request/mod.rs`, `src/agent/prompt_request/streaming.rs`
  - New `CompletionCall` struct: `call_index`, `usage: Option<Usage>`
  - `PromptResponse` and `TypedPromptResponse<T>` gain `completion_calls: Vec<CompletionCall>`
  - Non-streaming: `build_prepared_completion_request` returns executable/allowed tool names
  - Streaming: `MultiTurnStreamItem::CompletionCall` variant + `FinalResponse` gains content and completion_calls
  - Estimated: ~500 lines

- [x] **Tool Call Validation (agent-side)**
  - Upstream: `src/agent/completion.rs`, `src/agent/prompt_request/mod.rs`, `src/agent/prompt_request/streaming.rs`
  - `PreparedCompletionRequest` with `executable_tool_names` + `allowed_tool_names: BTreeSet<String>`
  - `allowed_tool_names_for_choice()` computes allowed set from `ToolChoice`
  - `validate_tool_call_name()` checks tool calls against allowed set
  - New `PromptError::UnknownToolCall { tool_name, available_tools, allowed_tools, chat_history }`
  - Streaming: `ToolCallDeltaState` buffers arguments until name validated, `build_tool_call_validation_history` for diagnostics
  - `build_completion_request` becomes thin wrapper around `build_prepared_completion_request`
  - Estimated: ~600 lines

- [x] **Null Tool Args Normalization**
  - Upstream: `src/tool/mod.rs` (`ToolDyn::call`)
  - When LLM sends `null` for tool arguments: fall back from `from_str("null")` → `from_str("{}")`
  - Only triggers when original parse fails AND input was `"null"`
  - Applied in both streaming and non-streaming tool invocation
  - Estimated: ~30 lines

- [x] **Anthropic Tool Cache Control**
  - Upstream: `src/providers/anthropic/completion.rs`, `src/providers/anthropic/streaming.rs`
  - `ToolDefinition` gains `cache_control: Option<CacheControl>` field
  - `build_tool_definitions` factors out tool construction from streaming
  - Streaming: last tool in list gets cache_control marker for breakpoint budgeting
  - `automatic_caching` respects raw top-level cache_control from additional_params
  - Estimated: ~200 lines

- [x] **OpenRouter Enhancements**
  - Upstream: `src/providers/openrouter/client.rs`, `src/providers/openrouter/completion.rs`, `src/providers/openrouter/streaming.rs`
  - Cache token accounting: `Usage::prompt_tokens_details` → `PromptTokensDetails { cached_tokens, cache_write_tokens }`
  - `GetTokenUsage` maps `cached_input_tokens`, `cache_creation_input_tokens`
  - App identity: `ClientBuilder::with_app_identity(title, url)` → `X-OpenRouter-Title` + `HTTP-Referer`
  - App categories: `ClientBuilder::with_app_categories(categories)` → `X-OpenRouter-Categories` (max 2)
  - Gemini role alias: `Assistant` gains `#[serde(alias = "model")]` for Gemini `"role": "model"`
  - Estimated: ~250 lines

- [x] **Gemini Tool Protocol & Streaming Metadata**
  - Upstream: `src/providers/gemini/completion.rs`, `src/providers/gemini/streaming.rs`
  - `FinishReason` gains: `UnexpectedToolCall`, `MissingThoughtSignature`, `TooManyToolCalls`, `MalformedResponse`
  - `function_call_finish_reason_error` converts to `CompletionError::ResponseError`
  - `tool_use_prompt_token_count` mapping to `Usage::tool_use_prompt_tokens`
  - Streaming: `finish_message: Option<String>` on response, `tool_protocol_finish_reason_error`, `stream_failed` guard
  - SSE parse errors now break stream instead of silent continue
  - Estimated: ~200 lines

- [x] **Ollama NDJSON Buffering**
  - Upstream: `src/providers/ollama.rs`
  - `NdjsonBuffer` struct reassembles NDJSON lines from chunked HTTP byte stream
  - Not applicable to Crystal: Crystal's HTTP client buffers the full response body before processing, so the chunked byte boundary issue doesn't exist (intentional_divergence)

- [x] **Agent hook() after tool()**
  - Upstream: `src/agent/builder.rs`
  - `.hook()` builder method moved from `NoToolConfig` impl to generic `ToolState` impl
  - `.tool(...).hook(...)` call chain now works
  - Estimated: ~10 lines (method move + test)

- [x] **Text Concatenation Fix**
  - Upstream: `src/providers/anthropic/completion.rs`, `src/agent/prompt_request/mod.rs`
  - `get_text_response` uses `.collect::<String>()` instead of `.join("\n")`
  - `assistant_text_from_choice` concatenates without inserting `\n` between blocks
  - Estimated: ~5 lines

- [x] **null_or_default JSON Deserializer**
  - Upstream: `src/json_utils.rs`
  - `null_or_default` deserializer: `null` → `T::default()` via `Option::<T>::deserialize().unwrap_or_default()`
  - Estimated: ~10 lines

## Companion Crates Ported

| Crate | Status | Crystal Location | Inventory |
|-------|--------|-----------------|-----------|
| `rig-memory` | ✅ Complete | `src/crig/memory.cr`, `src/crig/memory/policies.cr` | integrated into core inventory |
| `rig-vectorize` | ✅ Complete | `src/crig/vector_store/vectorize.cr` | `plans/inventory/vectorize/rust_port_inventory.tsv` (46 items) |
| `rig-sqlite` | ⬜ (separate repo `crig-sqlite`) | — | — |
| `rig-postgres` | ⬜ (separate repo `crig-postgres`) | — | — |
| `rig-qdrant` | ⬜ | — | — |
| `rig-mongodb` | ⬜ | — | — |
| `rig-lancedb` | ⬜ | — | — |
| `rig-milvus` | ⬜ | — | — |
| `rig-neo4j` | ⬜ | — | — |
| `rig-scylladb` | ⬜ | — | — |
| `rig-surrealdb` | ⬜ | — | — |
| `rig-helixdb` | ⬜ | — | — |
| `rig-s3vectors` | ⬜ | — | — |
| `rig-fastembed` | ⬜ | — | — |
| `rig-bedrock` | ⬜ | — | — |
| `rig-vertexai` | ⬜ | — | — |
| `rig-gemini-grpc` | ⬜ | — | — |
| `rig-derive` | ⬜ (N/A — Crystal macros) | — | — |
