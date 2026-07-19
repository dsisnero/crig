## Upstream Baseline

- **Repository**: `https://github.com/0xPlaygrounds/rig.git`
- **Crates**: `crates/rig-core`
- **Pinned upstream**: `06bc651f4c64d1673ba6af698f6c66602c5d313f` (rig-core v0.39.0)
- **Crystal tag**: `v0.40.0`

## v0.39.0 Features

**Detailed plan**: [plans/v39.md](./v39.md) — all 24 chunks completed (14 C + 10 R)

### Completed (24 chunks, 56 commits on `port/rig-v0.39.0`)
- [x] **C1-C14**: Core porting chunks (data types, agent state machine, runner, streaming, examples)
- [x] **R1**: Migrate PromptRequest.send() to AgentRunner
- [x] **R2**: Sync DeepSeek provider (thinking/tool_choice suppression)
- [x] **R3**: Sync OpenAI (Usage fields, from_http_response, composes_native_output)
- [x] **R4**: Sync Anthropic (coerce_tool_input, null citations, composes_native_output)
- [x] **R5**: Sync all remaining providers (Ollama, Cohere, Moonshot, Groq, etc. — from_http_response migration)
- [x] **R6**: Sync http_client module (remove Constant/Never, add non_success_status/body)
- [x] **R7**: ProviderResponseError helpers on all 7 capability errors
- [x] **R8**: AgentRun streaming support (StreamedTurnAssembler, streamed_turn, record_streamed_completion_call)
- [x] **R9**: Cleanup old hook types (PromptHook, HookAction, ToolCallHookAction — removed)
- [x] **R10**: Full JSON::Serializable on AgentRun (completion_calls, from_json)
- [ ] **R11**: ⬅️ you are here (this file) — inventory TSVs regeneration pending

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
