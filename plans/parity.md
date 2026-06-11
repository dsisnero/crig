## Upstream Baseline

- **Repository**: `https://github.com/0xPlaygrounds/rig.git`
- **Crates**: `crates/rig-core`
- **Previous baseline**: `a0cd8a8f505af70f10918e994bd45d8241ee4f37` (rig-core v0.37.0)
- **Latest upstream**: `536c44f9f3ef8cac10ead3535528c7ceab3497f9` (rig-core v0.38.x)
- **Commits behind**: 31 commits spanning v0.37.0 → v0.38.x

## v0.37.0 Features (completed)

- [x] Text::additional_params & Citation Support
- [x] tool_use_prompt_tokens on Usage
- [x] CompletionCall Tracking in Agent Responses
- [x] Tool Call Validation (agent-side)
- [x] Null Tool Args Normalization
- [x] Anthropic Tool Cache Control
- [x] OpenRouter Enhancements
- [x] Gemini Tool Protocol & Streaming Metadata
- [x] Ollama NDJSON Buffering (intentional_divergence)
- [x] Agent hook() after tool()
- [x] Text Concatenation Fix
- [x] null_or_default JSON Deserializer

## v0.38.x New Features (pending port)

### Feature Progress

- [x] **Invalid Tool Call Recovery Hooks**
  - Upstream: `src/agent/prompt_request/hooks.rs`, `src/agent/prompt_request/mod.rs`, `src/agent/prompt_request/streaming.rs`
  - New `InvalidToolCallContext` struct: tool_name, tool_call_id, internal_call_id, args, available_tools, allowed_tools, tool_choice, chat_history, is_streaming
  - New `InvalidToolCallHookAction` enum: Fail, Retry { feedback }, Repair { tool_name }, Skip { reason }
  - New `on_invalid_tool_call` method on `PromptHook` trait (default: fail-fast)
  - Non-streaming: `InvalidToolCallResolution` enum drives recovery flow; retry adds corrective user message, repair rewrites tool name, skip returns synthetic tool result
  - Streaming: validates tool calls against allowed names, applies hook recovery similarly
  - Estimated: ~1,600 lines of diff across hooks + prompt_request + streaming

- [x] **Anthropic Mid-Conversation System Messages**
  - Upstream: `src/providers/anthropic/completion.rs`
  - `Message::System { content }` variant accepted in chat history for Claude Opus 4.8+
  - `supports_mid_conversation_system_messages(model)` checks model compatibility
  - `is_valid_mid_conversation_system_message` + `assistant_ends_in_server_tool_block` helpers
  - System messages hoisted to top-level `system` array for older models
  - New model: `claude-opus-4-8`
  - Estimated: ~200 lines

- [x] **OpenRouter Prompt Caching**
  - Upstream: `src/providers/openrouter/completion.rs`
  - `CompletionModelBuilder::with_prompt_caching()` — enables cache_control on system prompt
  - `apply_prompt_caching(body)` — inserts `"cache_control": {"type": "ephemeral"}` on system message
  - `final_request_body()` handles prompt_caching + stream flags in additional_params
  - `ResponseImage` struct + `response_image_to_assistant_content` — avoids replaying generated images
  - `openrouter_response_image_params()` — identifies OpenRouter response images via additional_params
  - Estimated: ~300 lines

- [x] **Embeddings with Usage**
  - Upstream: `src/embeddings/embedding.rs`, `src/embeddings/builder.rs`
  - New `EmbeddingResponse` struct: `embeddings: Vec<Embedding>`, `usage: Usage`
  - `EmbeddingModel::embed_texts_with_usage(texts)` — default delegates to `embed_texts`, returns zero Usage
  - `EmbeddingModel::embed_text_with_usage(text)` — single-text convenience
  - Providers can override to expose real token usage from embedding API
  - Estimated: ~100 lines

- [x] **Tool Server append_toolset Tool Visibility Fix**
  - Upstream: `src/tool/server.rs`
  - `ToolServerHandle::append_toolset` now extends `static_tool_names` so merged tools are visible to LLM
  - Previously, tools added via `append_toolset` were callable but invisible to `get_tool_defs`
  - Estimated: ~5 lines (1 line fix + test)

- [x] **JSON Utils deserialize_json_string_or_value**
  - Upstream: `src/json_utils.rs`
  - New function `deserialize_json_string_or_value` — deserializes a field as either a JSON-encoded string or any other JSON value into `Option<String>`
  - Tolerates OpenAI-compatible gateways that stream tool-call arguments as objects `{}` instead of strings `"{}"`
  - null and missing fields become None
  - Applied to OpenAI streaming `tool_calls[].function.arguments`
  - Estimated: ~30 lines

- [x] **Gemini tool_parameters_to_schema Improvements**
  - Upstream: `src/providers/gemini/completion.rs`
  - New `tool_parameters_to_schema(parameters)` extracts Gemini-compatible Schema from JSON params
  - Handles nullable type arrays, `$defs`/`$ref` resolution, composition objects
  - Improved enum extraction from both top-level and nested property sources
  - Estimated: ~200 lines

- [x] **OpenAI Responses API Token Usage Details**
  - Upstream: `src/providers/openai/responses_api/mod.rs`
  - Token usage details (input_tokens_details, output_tokens_details) made optional
  - Handle missing details gracefully without panicking
  - Estimated: ~15 lines

## Remaining Gaps (post v0.38.x parity)

- [x] **OpenAI/VoyageAI Embeddings with Usage provider overrides**
  - Upstream: `src/providers/openai/embedding.rs` (+31), `src/providers/voyageai.rs` (+27)
  - `embed_texts_with_usage` overrides that map provider-specific usage fields (prompt_tokens_details.cached_tokens, etc.)
  - Crystal has `EmbeddingResponse` data model and `EmbeddingModel` trait defaults already

- [x] **Copilot streaming internal_call_id generation**
  - Upstream: `src/providers/copilot/mod.rs` (+20)
  - Tool call deltas now get nanoid-generated internal_call_id instead of empty strings
  - Crystal Copilot streaming is simpler (text-only); tool call delta handling deferred (intentional_divergence)

- [x] **OpenAI responses_api unreplayable reasoning detection**
  - Upstream: `src/providers/openai/responses_api/mod.rs`
  - `has_unreplayable_reasoning` / `cannot_replay_as_provider_output` logic
  - Routes content as InputText vs OutputText based on whether reasoning has provider ID

- [x] **OpenRouter ResponseImage replay avoidance**
  - Upstream: `src/providers/openrouter/completion.rs`
  - `ResponseImage` struct, `response_image_to_assistant_content`, `is_openrouter_response_image`
  - Prevents replaying generated images in multi-turn history by tagging with `additional_params`

- [x] **Agent prompt_request InvalidToolCallResolution integration**
  - Upstream: `src/agent/prompt_request/mod.rs` (+1066), `src/agent/prompt_request/streaming.rs` (+2136)
  - Non-streaming: `InvalidToolCallResolution` recovery flow (retry/repair/skip) wired into tool execution loop
  - Streaming: `ToolCallValidationHistory`, `flush_pending_reasoning_delta`, tool call validation with hook recovery
  - `max_invalid_tool_call_retries` budget on `PromptRequest`
  - `resolve_invalid_tool_call` orchestrates hook callback, retry, repair name revalidation
  - Data model ported; loop integration deferred (touches core multi-turn agent state machine)

- [ ] **OpenAI responses_api unreplayable reasoning detection**
  - Upstream: `src/providers/openai/responses_api/mod.rs`
  - `has_unreplayable_reasoning` / `cannot_replay_as_provider_output` logic
  - Routes content as InputText vs OutputText based on whether reasoning has provider ID

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
