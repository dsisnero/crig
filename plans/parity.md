## Upstream Baseline

- **Repository**: `https://github.com/0xPlaygrounds/rig.git`
- **Crates**: `crates/rig-core`
- **Pinned upstream**: `06bc651f4c64d1673ba6af698f6c66602c5d313f` (rig-core v0.39.0)
- **Crystal tag**: `v0.40.0`

## v0.39.0 Features

**Detailed plan**: [plans/v39.md](./v39.md) — 14 completed chunks, 11 remaining with red-green TDD

### Completed (13 chunks, 45 commits on `port/rig-v0.39.0`)
- [x] **C1**: Delete upstream-removed modules (pipeline, buffered, old hooks)
- [x] **C2**: Port new data-type modules (id, rerank, provider_response)
- [x] **C3**: Structured tool results (ToolFailure, ToolOutcome, ToolExecutionResult)
- [x] **C4**: Hook system v2 data types (RunId, Scratchpad, HookContext, RequestPatch, Flow)
- [x] **C5**: AgentRun state machine (next_step, model_response, tool_results)
- [x] **C6**: AgentRunner sequential (run, hook dispatch, patch merging)
- [x] **C7**: Concurrent tool execution (errgroup pattern)
- [x] **C8**: Streaming drive_agent (channel generator)
- [x] **C9**: Scratchpad Mutex safety
- [x] **C10**: Wire Agent → AgentRunner bridge
- [x] **C11**: Fix agent-as-tool crash (ToolType removal, spawn fix)
- [x] **C12**: Fix assistant message + tool result format
- [x] **C13**: Port all v0.39.0 vendor examples (8 examples)
- [x] **C14**: Convenience API (AgentRun.new(String), tool_result(id, text))

### Remaining (11 chunks — see [plans/v39.md](./v39.md))
- [ ] R1: Migrate PromptRequest.send() to AgentRunner
- [ ] R2-R5: Sync providers (DeepSeek, OpenAI, Anthropic, 10 others)
- [ ] R6: Sync http_client module
- [ ] R7: ProviderResponseError helpers on all capability errors
- [ ] R8: AgentRun streaming support (streamed.rs)
- [ ] R9: Cleanup old hook types (PromptHook, HookAction)
- [ ] R10: Full JSON::Serializable on AgentRun
- [ ] R11: Update inventory TSVs

## v0.38.x Features (completed)

- [x] Text::additional_params & Citation Support (22 tests)
- [x] tool_use_prompt_tokens on Usage (4 tests)
- [x] CompletionCall Tracking in Agent Responses (6 tests)
- [x] Tool Call Validation (agent-side) (4 tests)
- [x] Null Tool Args Normalization (2 tests)
- [x] Anthropic Tool Cache Control (2 tests)
- [x] OpenRouter Enhancements (5 tests)
- [x] Gemini Tool Protocol & Streaming Metadata (4 tests)
- [x] Ollama NDJSON Buffering (intentional_divergence)
- [x] Agent hook() after tool() (1 test)
- [x] Text Concatenation Fix (2 tests)
- [x] null_or_default JSON Deserializer (2 tests)

## v0.38.x Features (completed)

- [x] Invalid Tool Call Recovery Hooks (10 tests)
- [x] Anthropic Mid-Conversation System Messages (5 tests)
- [x] OpenRouter Prompt Caching (3 tests)
- [x] Embeddings with Usage (3 tests)
- [x] Tool Server append_toolset Visibility Fix (1 test)
- [x] JSON Utils deserialize_json_string_or_value (6 tests)
- [x] Gemini tool_parameters_to_schema Improvements (already ported)
- [x] OpenAI Responses API Token Usage Details (already nilable)

## Remaining Gaps (all completed)

- [x] OpenAI/VoyageAI Embeddings with Usage provider overrides (trait supports)
- [x] Copilot streaming internal_call_id (intentional_divergence)
- [x] OpenAI responses_api unreplayable reasoning detection (2 tests)
- [x] OpenRouter ResponseImage replay avoidance (3 tests)
- [x] Agent prompt_request InvalidToolCallResolution integration (6 tests)

## Minor Items (not yet tracked in inventory)

These upstream API items are ported but their inventory TSV rows need updating:

- [ ] `src/providers/anthropic/completion.rs::const::CLAUDE_OPUS_4_8` — model constant
- [ ] `src/providers/anthropic/completion.rs::func::anthropic_citations` — citations extractor from Text::additional_params
- [ ] `src/test_utils/streaming.rs::func::text_start`, `text_additional_params` — RawStreamingChoice factory helpers
- [ ] `src/providers/openrouter/completion.rs::func::with_prompt_caching` — CompletionModel builder method

## Companion Crates Ported

| Crate | Status | Crystal Location |
|-------|--------|-----------------|
| `rig-memory` | ✅ Complete | `src/crig/memory.cr`, `src/crig/memory/policies.cr` |
| `rig-vectorize` | ✅ Complete | `src/crig/vector_store/vectorize.cr` |
| `rig-sqlite` | ⬜ (separate repo) | — |
| `rig-postgres` | ⬜ (separate repo) | — |
| `rig-qdrant` | ⬜ | — |
| `rig-mongodb` | ⬜ | — |
| `rig-lancedb` | ⬜ | — |
| `rig-milvus` | ⬜ | — |
| `rig-neo4j` | ⬜ | — |
| `rig-scylladb` | ⬜ | — |
| `rig-surrealdb` | ⬜ | — |
| `rig-helixdb` | ⬜ | — |
| `rig-s3vectors` | ⬜ | — |
| `rig-fastembed` | ⬜ | — |
| `rig-bedrock` | ⬜ | — |
| `rig-vertexai` | ⬜ | — |
| `rig-gemini-grpc` | ⬜ | — |
| `rig-derive` | ⬜ (N/A — Crystal macros) | — |
