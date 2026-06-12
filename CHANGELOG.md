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
