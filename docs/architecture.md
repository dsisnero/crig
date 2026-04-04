# Architecture

`crig` is a Crystal implementation of Rig's `rig-core` architecture, not just a loose
wrapper around provider HTTP calls. The codebase keeps the same major subsystem
boundaries as upstream and preserves the same public workflows where possible.

## Source of Truth

- Upstream repository: `https://github.com/0xPlaygrounds/rig.git`
- Pinned checkout: `vendor/rig`
- Target crate: `vendor/rig/rig/rig-core`
- Pinned baseline commit: `f5c4812de02e776d9a68b481a8cf71ed6b572a2d`

Rust source, tests, and fixtures define the expected behavior for tracked parity
work. Crystal adaptations are acceptable only where the languages differ
structurally, with concurrency being the main approved example.

## Public API Shape

The public API is intentionally builder-heavy.

Most workflows begin at a provider client and branch into one of the following
builder entry points:

- `client.agent(model)`
- `client.extractor(Type, model)`
- `client.embeddings(model)`
- `client.embeddings_with_ndims(model, ndims)`
- `model.completion_request(prompt)`
- `model.transcription_request`
- `model.image_generation_request`
- `model.audio_generation_request`

This mirrors how the Rust crate is meant to be used:

1. choose a provider client
2. choose a model
3. configure behavior through chained builders
4. build or send the request

## Core Subsystems

### Clients and Provider Models

Provider clients live under `src/crig/providers/*`. They construct concrete model
types for the capabilities they support:

- completion models
- embedding models
- transcription models
- image generation models
- audio generation models

The shared client mixins in `src/crig/client/*` provide the ergonomic builder entry
points that examples use.

### Agents

Agents are assembled through `Crig::AgentBuilder` in
[`src/crig/agent.cr`](../src/crig/agent.cr).

An agent builder combines:

- model selection
- preamble and static context
- dynamic retrieval sources
- static tools
- dynamic tools
- tool server handles
- output schemas
- generation parameters such as temperature and max tokens

`build` freezes those inputs into a concrete `Crig::Agent`, which then exposes:

- prompt requests
- chat requests
- typed prompt requests
- streaming prompt requests
- nested agent tool behavior

### Extractors

Extractors are not a Crystal-only shortcut. They follow the same submit-tool strategy
used upstream, and they are built through `client.extractor(...)` or
`Crig::ExtractorBuilder`.

This matters because the extractor runtime is shared by:

- direct extraction
- evaluation metrics such as `LlmJudgeBuilder`
- typed output workflows

### Embeddings and Vector Stores

Embeddings live under `src/crig/embeddings*` and vector stores under
`src/crig/vector_store*`.

The important architectural rule is that embeddings are also builder-first:

- client creates the model
- model feeds an embeddings builder
- builder accumulates documents
- `build` batches embedding calls according to model constraints

Vector search is layered on top of that:

- `VectorSearchRequest.builder`
- `InMemoryVectorStore.builder`
- `store.index(model)`
- `top_n`, `top_n_ids`, and `top_n_results`

### Tools and Tool Servers

Tools live in `src/crig/tool.cr` and are composed into `ToolSet` and `ToolServer`.

There are three main modes:

- static tools
- embedding-backed tools
- MCP-backed tools

`ToolServer` is the runtime coordinator for agent tool execution, and builder-managed
tools are expected to flow through the real tool-server path rather than bypassing it.

### Streaming

Streaming is implemented in `src/crig/streaming.cr`.

The public API follows Rig's streaming model, but the runtime adaptation is Crystal
specific:

- Rust upstream uses async streams and futures
- `crig` uses fibers plus `Channel`

The important consequence is that the user-facing model stays the same:

- providers emit raw streaming choices
- `StreamingCompletionResponse` aggregates them into assistant content
- pause, resume, cancel, and final-response handling live in the streaming wrapper

## Concurrency Model

The allowed architectural difference from upstream is the concurrency primitive.

In this repository:

- synchronous calls remain the default public path
- async helpers use channel-backed wrappers
- parallel composition uses fibers and channels
- tool server and streaming coordination also use channels

This keeps the code idiomatic for Crystal while preserving the same logical request
boundaries and runtime stages as the Rust implementation.

## Integrations

The repository currently includes first-class integrations for:

- CLI chatbots
- Discord bots
- MCP / RMCP-backed tool servers
- SQLite and PostgreSQL vector-store examples

These are real integration surfaces, not placeholder directories. The README should
therefore describe them as part of the shipped library surface whenever they are
implemented in `src/`.

## Documentation Rule

Top-level docs should describe what exists in the current Crystal codebase.

That means:

- do not reduce the repo description to “this is a port”
- do describe the actual public APIs in `src/`
- do emphasize the builder APIs because they are the primary ergonomic surface
- do mention parity constraints, but only after describing the current library

## Maintenance Rule

Every substantive API addition or parity correction should keep these in sync:

- `README.md`
- `docs/architecture.md`
- `plans/inventory/rust_port_inventory.tsv`
- `plans/inventory/rust_source_parity.tsv`
- `plans/inventory/rust_test_parity.tsv`
