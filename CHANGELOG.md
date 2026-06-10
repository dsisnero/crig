# Changelog

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
