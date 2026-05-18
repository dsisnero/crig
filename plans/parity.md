# Crystal Parity Plan — rig-core

**Baseline**: `vendor/rig/crates/rig-core` @ commit `f77a5819ec2a71e98583480a68a341f816a75c8a`
**Previous pinned**: `013d65a3f5d0a3cbf5a712826c343a3526d13112`
**Delta**: +92 commits, repo restructured from `rig/rig-core/` → `crates/rig-core/`
**Last updated**: 2026-05-17

---

## Overview

The upstream Rust crate grew from 141 source files to 173 (+33 new, -1 removed).
AGENTS.md and parity scripts have been updated to reference the new `crates/rig-core` path.
AppleDouble `._*` artifacts were purged from both vendor and source trees.

The parity inventory shows **477 unmatched items** spanning new modules, new API surface
in existing modules, and new tests. What follows is a work breakdown in dependency order.

---

## Metaproject / Infrastructure

- [x] Update `vendor/rig` submodule to latest `main` (`f77a5819`)
- [x] Update AGENTS.md pinned commit and crate path (`crates/rig-core`)
- [x] Purge AppleDouble `._*` files from vendor and src trees
- [x] Fix Ruby `parity_inventory_lib.rb` to handle non-UTF-8 bytes gracefully
- [x] Re-run `ensure_parity_plan.sh` with `REFRESH=1` to regenerate source/test parity inventories
- [ ] Run `verify_parity_adversarial.sh` and record baseline failures
- [x] Ensure `mcp` shard installs (`shards install`) so `make test` passes

---

## Core Modules

### 1. `memory` module (NEW)

Rust `src/memory.rs` — conversation memory management, compaction, and demotion.

| Item | Kind | Status |
|------|------|--------|
| `ConversationMemory` trait | trait | [x] |
| `MemoryError` enum | enum | [x] |
| `InMemoryConversationMemory` struct | struct | [x] |
| `Compactor` trait | trait | [x] |
| `DemotionHook` trait | trait | [x] |
| `MessageFilter` trait | trait | [x] |
| `NoopDemotionHook` struct | struct | [x] |
| All `#[test]` functions (≥15 tests) | test | [x] |

**Work**: ~~Create `src/crig/memory.cr` with equivalent types and specs.~~ Done.

### 2. `markers` module (NEW)

Rust `src/markers.rs` — type-state markers (`Missing`, `Provided`) used in builder patterns.

| Item | Kind | Status |
|------|------|--------|
| `Missing` struct | struct | [x] |
| `Provided` struct | struct | [x] |

**Work**: ~~Create `src/crig/markers.cr`. Trivial port — these are empty unit structs.~~ Done.

### 3. Agent module — new sub-files

Rust split `agent.rs` into multiple files. Crystal currently has a monolithic `agent.cr` (645 LOC).

| Rust file | Crystal status |
|-----------|---------------|
| `agent/builder.rs` — `AgentBuilder` API changes | [x] needs diff review — memory fields added |
| `agent/completion.rs` — `CompletionAgent` | [x] review for additions |
| `agent/prompt_request/hooks.rs` (NEW) — tool hooks | [x] already ported in prompt_request.cr |
| `agent/prompt_request/mod.rs` — new API surface | [x] ported `conversation()`, `without_memory()` |
| `agent/prompt_request/streaming.rs` — new streaming helpers | [x] ported `conversation()`, `without_memory()` |
| `agent/tool.rs` (NEW) — tool integration | [x] already ported as AgentToolAdapter(M) |

**Work**: ~~Review diffs in existing agent files; add `hooks.cr`, `tool.cr`, new methods.~~ Done.

### 4. Completion module — new additions

| Item | Kind | Status |
|------|------|--------|
| `completion/message.rs` — `file_id()` function | func | [ ] |

**Work**: Add `FileId` variant to `DocumentSourceKind`. Deferred — touches 116 exhaustive pattern matches across all providers.

### 5. `audio_generation` module — new builder methods

| Item | Kind | Status |
|------|------|--------|
| `AudioGenerationRequestBuilder.build()` | method | [x] |
| `AudioGenerationRequestBuilder.text()` | method | [x] |

### 6. `image_generation` module — new builder methods

| Item | Kind | Status |
|------|------|--------|
| `ImageGenerationRequestBuilder.build()` | method | [x] |
| `ImageGenerationRequestBuilder.prompt()` | method | [x] |

### 7. `transcription` module — builder methods

| Item | Kind | Status |
|------|------|--------|
| `TranscriptionRequestBuilder.build()` | method | [x] |
| `TranscriptionRequestBuilder.filename()` | method | [x] |

### 8. `vector_store/request` module

| Item | Kind | Status |
|------|------|--------|
| `VectorSearchRequestBuilder.build()` | method | [x] |

### 9. `http_client/sse` module

| Item | Kind | Status |
|------|------|--------|
| `allow_missing_content_type()` | func | [x] |

### 10. `client/mod` module

| Item | Kind | Status |
|------|------|--------|
| `ProviderClientError` enum | enum | [x] |
| `ProviderClientResult` type alias | type | [x] (as union type) |
| `get_base_url()` | func | [x] (per-provider) |
| `optional_env_var()` | func | [x] |
| `required_env_var()` | func | [x] |

### 11. `model/listing` — new tests

Rust added 4 new tests for error formatting and preview truncation.

**Work**: Port `test_format_response_body_preview_*` and `test_*_error_with_context_*` tests.

---

## Provider Modules

### 12. `chatgpt` provider (NEW)

Rust introduced a full ChatGPT provider with OAuth device-code auth, Responses API support,
and streaming. This is a large module.

| Item | Kind | Status |
|------|------|--------|
| `AuthError`, `AuthSource`, `AuthContext`, `Authenticator` | enums/structs | [ ] |
| `DeviceCodeHandler`, `DeviceCodePrompt` | structs | [ ] |
| `ChatGPTBuilder`, `ChatGPTExt` builder pattern | structs | [ ] |
| `ResponsesCompletionModel` | struct | [ ] |
| `ChatGPTAuth` enum | enum | [ ] |
| `GPT_5_4`, `GPT_5_3_*` model constants | consts | [ ] |
| Auth: `native.rs` and `wasm.rs` implementations | impl | [ ] |
| All `#[test]` functions (~8 tests) | test | [ ] |

**Work**: Create `src/crig/providers/chatgpt.cr` (or sub-directory) with full provider and specs.

### 13. `copilot` provider (NEW)

Rust introduced a GitHub Copilot provider with OAuth device-code auth, completion/embedding,
and strict tool support.

| Item | Kind | Status |
|------|------|--------|
| `AuthError`, `AuthSource`, `AuthContext`, `Authenticator` | enums/structs | [ ] |
| `CopilotBuilder`, `CopilotExt` builder pattern | structs | [ ] |
| `CopilotCompletionResponse`, `CopilotStreamingResponse` | enums | [ ] |
| `CompletionModel`, `EmbeddingModel`, `CopilotModelLister` | structs | [ ] |
| `CopilotAuth` enum | enum | [ ] |
| Auth: `native.rs` and `wasm.rs` implementations | impl | [ ] |
| All `#[test]` functions (~12 tests) | test | [ ] |

**Work**: Create `src/crig/providers/copilot.cr` with full provider and specs.

### 14. `minimax` provider (NEW)

| Item | Kind | Status |
|------|------|--------|
| `MiniMaxBuilder`, `MiniMaxExt` + `MiniMaxAnthropic*` | structs | [ ] |
| `Client`, `ClientBuilder`, `AnthropicClient`, `AnthropicClientBuilder` | types | [ ] |
| All model constants (`MINIMAX_M2_*`) | consts | [ ] |
| Base URL constants (global, china, anthropic) | consts | [ ] |
| All `#[test]` functions (~4 tests) | test | [ ] |

**Work**: Create `src/crig/providers/minimax.cr`.

### 15. `zai` provider (NEW)

| Item | Kind | Status |
|------|------|--------|
| `ZAiBuilder`, `ZAiExt` + `ZAiAnthropic*` | structs | [ ] |
| `Client`, `ClientBuilder`, `AnthropicClient`, `AnthropicClientBuilder` | types | [ ] |
| All model constants (`GLM_4_5*`, `GLM_4_6*`) | consts | [ ] |
| Base URL constants (general, coding, anthropic) | consts | [ ] |
| All `#[test]` functions (~4 tests) | test | [ ] |

**Work**: Create `src/crig/providers/zai.cr`.

### 16. `xiaomimimo` provider — rename/rewrite

Crystal has `src/crig/providers/xiaomi.cr` (389 LOC). The Rust module was renamed to
`xiaomimimo.rs` and significantly expanded (~580 LOC diff).

| Item | Kind | Status |
|------|------|--------|
| Rename `xiaomi.cr` → `xiaomimimo.cr` | refactor | [ ] |
| `XiaomiMimoBuilder`, `XiaomiMimoExt` + `XiaomiMimoAnthropic*` | structs | [ ] (existing may need updates) |
| `Client`, `ClientBuilder`, `AnthropicClient`, `AnthropicClientBuilder` | types | [ ] (existing may need updates) |
| New model constants (`MIMO_V2_5_PRO`, `MIMO_V2_FLASH`, `MIMO_V2_OMNI`) | consts | [ ] |
| All `#[test]` functions (~4 tests) | test | [ ] |
| Review diff for API changes | audit | [ ] |

### 17. `providers/internal/` module (NEW)

| Item | Kind | Status |
|------|------|--------|
| `internal/buffered.rs` — buffered request/response helpers | module | [ ] |
| `internal/openai_chat_completions_compatible.rs` — shared OpenAI-compat logic | module | [ ] |
| All `#[test]` functions (~5 tool-call/eof-cleanup tests) | test | [ ] |

**Work**: Create `src/crig/providers/internal/` directory with `buffered.cr` and `openai_chat_completions_compatible.cr`.

### 18. OpenRouter provider — new sub-modules

| Item | Kind | Status |
|------|------|--------|
| `openrouter/audio_generation.rs` — TTS support | module | [ ] |
| `openrouter/transcription.rs` — STT support | module | [ ] |
| `openrouter/model_listing.rs` — model listing | module | [ ] |

**Work**: Add to existing `src/crig/providers/openrouter/` directory.

### 19. OpenAI provider — new sub-modules

| Item | Kind | Status |
|------|------|--------|
| `openai/audio_generation.rs` | module | [ ] |
| `openai/image_generation.rs` — `GPT_IMAGE_1_5`, `GPT_IMAGE_2` | module | [ ] |
| `openai/transcription.rs` | module | [ ] |
| `openai/model_listing.rs` — `OpenAIModelLister` | module | [ ] |
| `openai/completion/mod.rs` — `GenericCompletionModel`, `FileData`, `GPT_5_5` | updates | [ ] |
| `openai/responses_api/mod.rs` — `GenericResponsesCompletionModel` | updates | [ ] |
| `openai/embedding.rs` — `GenericEmbeddingModel` | updates | [ ] |

### 20. Anthropic provider — new sub-modules

| Item | Kind | Status |
|------|------|--------|
| `anthropic/model_listing.rs` — `AnthropicModelLister` | module | [ ] |
| `anthropic/completion.rs` — `GenericCompletionModel`, `AnthropicCompatibleProvider` | updates | [ ] |
| `anthropic/completion.rs` — new model consts (`CLAUDE_HAIKU_4_5`, `CLAUDE_OPUS_4_6/7`, `CLAUDE_SONNET_4_6`) | consts | [ ] |

### 21. Gemini provider — new sub-modules

| Item | Kind | Status |
|------|------|--------|
| `gemini/model_listing.rs` — `GeminiInteractionsModelLister`, `GeminiModelLister` | module | [ ] |
| `gemini/completion.rs` — `Modality`, `TrafficType`, `ModalityTokenCount` | types | [ ] |
| Streaming finish_reason/model_version additions | updates | [ ] |

### 22. Mistral provider — new sub-modules

| Item | Kind | Status |
|------|------|--------|
| `mistral/model_listing.rs` — `MistralModelLister` | module | [ ] |
| `mistral/client.rs` — `PromptTokensDetails`, `cached_tokens()` | updates | [ ] |

### 23. Provider updates (existing, diff review needed)

These Crystal providers need diff review against their Rust counterparts for new
constants, API signatures, and test coverage:

| Crystal file | Rust commits to review |
|-------------|----------------------|
| `providers/ollama.cr` (910 LOC) | `think` string levels, `OllamaApiKey`, `OllamaModelLister` |
| `providers/deepseek.cr` (841 LOC) | `DEEPSEEK_V4_FLASH`, `DEEPSEEK_V4_PRO`, `DeepSeekModelLister` |
| `providers/azure.cr` (698 LOC) | ~1,188 lines of upstream changes |
| `providers/llamafile.cr` (131 LOC) | ~867 lines of upstream changes (many are tests) |
| `providers/mira.cr` (451 LOC) | ~830 lines of upstream changes |
| `providers/moonshot.cr` (385 LOC) | ~798 lines of upstream changes + new anthropic compat |
| `providers/groq.cr` (498 LOC) | ~790 lines of upstream changes |
| `providers/huggingface.cr` | ~1,332 lines of upstream changes + image_generation, transcription |
| `providers/cohere.cr` | ~824 lines of upstream changes |
| `providers/together.cr` | review diff |
| `providers/perplexity.cr` | review diff |
| `providers/voyageai.cr` | review diff |
| `providers/hyperbolic.cr` | review diff |
| `providers/galadriel.cr` | review diff |
| `providers/xai.cr` | review diff |

---

## Test Utilities (NEW)

Rust introduced `crates/rig-core/src/test_utils/` — reusable test doubles.

| File | Contents | Status |
|------|----------|--------|
| `test_utils/mod.rs` | Module assembly | [ ] |
| `test_utils/completion.rs` | `MockCompletionModel`, `MockTurn`, `MockError` | [ ] |
| `test_utils/embeddings.rs` | `MockEmbeddingModel`, `MockTextDocument`, `MockMultiTextDocument` | [ ] |
| `test_utils/http.rs` | `RecordingHttpClient`, `MockStreamingClient`, `SequencedStreamingHttpClient`, `MockHttpResponse`, `CapturedHttpRequest` | [ ] |
| `test_utils/memory.rs` | `CountingMemory`, `FailingMemory`, `AppendFailingMemory` | [ ] |
| `test_utils/model_listing.rs` | `MockModelLister` | [ ] |
| `test_utils/pipeline.rs` | `MockPromptModel`, `MockVectorStoreIndex`, `Foo` | [ ] |
| `test_utils/streaming.rs` | `MockResponse`, `MockStreamEvent` | [ ] |
| `test_utils/tools.rs` | `MockAddTool`, `MockSubtractTool`, `MockToolIndex`, `BarrierMockToolIndex`, etc. | [ ] |
| `test_utils/internal_streaming_profiles.rs` | Internal streaming profiles | [ ] |

**Work**: Create `src/crig/test_utils/` directory with all fixture modules. Mark feature-gated
behind a `test_utils` compilation flag (Crystal macros or conditional require).

---

## Removed File

| Rust file removed | Crystal equivalent | Status |
|------------------|-------------------|--------|
| `client/builder.rs` | `src/crig/client/builder.cr` exists | [ ] audit if still needed |

---

## Spec Coverage Gap

Rust has **70 files** with `#[test]` annotations across rig-core.
Crystal has **34 spec files** (including AppleDouble duplicates — real count is ~17 unique files).

Priority test areas with zero coverage:
- ~~Agent hooks, tool integration~~ (covered in spec/crig_spec.cr)
- ~~Memory (ConversationMemory, Compactor, DemotionHook)~~ (spec/memory_spec.cr)
- ~~http_client SSE (allow_missing_content_type)~~ (covered)
- Transcription, audio_generation, image_generation
- chatgpt, copilot, minimax, zai, xiaomimimo providers
- model_listing for anthropic, gemini, mistral, openai, openrouter
- openai responses_api (completion response tiers, file_id documents)
- streaming metadata (finish_reason, model_version on gemini)
- vector_store builder

---

## Suggested Work Order

1. **Infrastructure**: Fix parity scripts, get `make test` passing
2. **Core module: `markers.cr`** (trivial, unblocks builders)
3. **Core module: `memory.cr`** (new, self-contained, medium size)
4. **Agent**: hooks and tool sub-modules
5. **Client/Completion**: `file_id()`, `ProviderClientError`, missing builder methods
6. **Provider: `internal/`** (shared infra for other providers)
7. **Provider: `xiaomimimo` rename + diff review**
8. **Provider: `minimax`, `zai`** (similar pattern, ~400 LOC each)
9. **Provider: `chatgpt`** (largest new provider, auth system)
10. **Provider: `copilot`** (auth system, similar to chatgpt)
11. **Provider model_listing**: anthropic, gemini, mistral, openai, openrouter
12. **Provider audio/transcription**: openrouter, openai
13. **Diff review**: ollama, deepseek, azure, llamafile, mira, moonshot, groq
14. **Diff review**: huggingface, cohere, together, perplexity, voyageai, hyperbolic, galadriel, xai
15. **Test utilities**: all test_utils modules
16. **Spec coverage**: write tests for all new and updated modules
