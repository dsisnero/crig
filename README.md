# crig

`crig` is a Crystal library for building modular, builder-first LLM applications.

It ports the public behavior of Rig's Rust `rig-core` crate into Crystal, but the
goal of this repository is not just parity bookkeeping. The current codebase already
includes agents, extractors, provider clients, embeddings, vector stores, streaming,
tool servers, CLI/Discord integrations, and a large example/spec surface.

Current upstream parity source:
- Repository: `https://github.com/0xPlaygrounds/rig.git`
- Submodule path: `vendor/rig`
- Rust crate under port: `vendor/rig/rig/rig-core`
- Pinned upstream commit: `f5c4812de02e776d9a68b481a8cf71ed6b572a2d`

## Table of Contents

- [What is crig?](#what-is-crig)
- [High-level Features](#high-level-features)
- [Get Started](#get-started)
  - [Simple Example](#simple-example)
  - [Embeddings builder example](#embeddings-builder-example)
  - [Vector search example](#vector-search-example)
- [Providers and Capabilities](#providers-and-capabilities)
- [Examples](#examples)
- [Architecture](#architecture)
- [Development](#development)
- [Upstream Relationship](#upstream-relationship)

## What is crig?

`crig` gives Crystal applications a unified interface for:

- completion models
- agent builders and prompt requests
- structured extraction
- embeddings and vector search
- tool calling and tool servers
- streaming responses
- transcription, audio generation, and image generation

The dominant usage style is builder-based. In practice, most workflows start from a
provider client and then branch into ergonomic builder entry points such as:

- `client.agent(model)`
- `client.extractor(Type, model)`
- `client.embeddings(model)`
- `model.completion_request(prompt)`
- `model.transcription_request`
- `model.image_generation_request`
- `model.audio_generation_request`

## High-level Features

- Builder-first public API modeled after Rig's Rust surface.
- Multi-provider completion support under a shared client/model abstraction.
- Agent workflows with static context, dynamic context, tools, tool servers, and multi-turn prompting.
- Channel-backed streaming and async helpers using Crystal fibers instead of Rust futures.
- Structured extraction through the same submit-tool strategy used upstream.
- Embeddings builders, vector stores, in-memory search, and dynamic retrieval pipelines.
- Tool definitions, embedding-backed tools, MCP-backed tools, and channel-based tool server execution.
- Support for transcription, audio generation, and image generation where providers expose those capabilities.
- A large and growing example suite ported from upstream `rig-core/examples`.

## Get Started

Until the API stabilizes, the safest way to consume `crig` is from Git:

```yaml
dependencies:
  crig:
    github: dsisnero/crig
```

Then:

```bash
shards install
```

### Simple Example

```crystal
require "crig"

client = Crig::Providers::OpenAI::Client.from_env

comedian = client
  .agent("gpt-5.2")
  .preamble("You are a comedian here to entertain the user using humour and jokes.")
  .build

puts comedian.prompt("Entertain me!").send
```

### Embeddings builder example

```crystal
require "crig"

client = Crig::Providers::OpenAI::Client.from_env

embeddings = client
  .embeddings("text-embedding-3-large")
  .simple_document("doc0", "Hello, world!")
  .simple_document("doc1", "Goodbye, world!")
  .build
```

You can also use explicit dimensions when the model name does not carry enough
information:

```crystal
builder = client.embeddings_with_ndims("custom-model", 3072)
```

### Vector search example

```crystal
require "crig"

embedding_model = Crig::Providers::OpenAI::Client.from_env
  .embedding_model("text-embedding-3-large")

documents = Crig::Embeddings::EmbeddingsBuilder.new(embedding_model)
  .simple_document("doc0", "Crystal is a compiled language.")
  .simple_document("doc1", "Rig is a library for LLM applications.")
  .build

store = Crig::InMemoryVectorStore(Crig::SimpleDocument)
  .builder
  .documents_with_id_f(documents) { |document| document.id }
  .build

request = Crig::VectorSearchRequest.builder
  .query("What is Crystal?")
  .samples(1)
  .build

pp store.index(embedding_model).top_n_results(request)
```

## Providers and Capabilities

Current provider surface in `src/crig/providers` includes:

- OpenAI
- Anthropic
- Azure OpenAI
- Cohere
- DeepSeek
- Galadriel
- Gemini
- Groq
- Hugging Face
- Hyperbolic
- Mira
- Mistral
- Moonshot
- Ollama
- OpenRouter
- Perplexity
- Together
- VoyageAI
- xAI
- Xiaomi

Capabilities vary by provider, but the repo currently includes implementations for:

- completion
- streaming completion
- embeddings
- transcription
- image generation
- audio generation

Companion integration examples also exist for:

- SQLite vector stores
- PostgreSQL vector stores
- MCP / RMCP tool servers
- CLI chatbots
- Discord bots

## Examples

The repository ships a substantial example surface under [`examples/`](./examples), including:

- basic agents
- context and loader-backed agents
- nested agent tools
- structured output
- extractors
- streaming
- embeddings
- vector search and RAG
- multi-agent orchestration patterns
- provider-specific examples for OpenAI, Anthropic, DeepSeek, Gemini, Groq, Hugging Face, Ollama, Together, xAI, and others

Representative files:

- [`examples/agent.cr`](./examples/agent.cr)
- [`examples/agent_with_tools.cr`](./examples/agent_with_tools.cr)
- [`examples/openai_streaming.cr`](./examples/openai_streaming.cr)
- [`examples/gemini_embeddings.cr`](./examples/gemini_embeddings.cr)
- [`examples/vector_search.cr`](./examples/vector_search.cr)
- [`examples/rmcp.cr`](./examples/rmcp.cr)

## Architecture

`crig` follows the same high-level decomposition as `rig-core`, with Crystal-native
execution underneath:

- clients construct provider-specific models
- client mixins expose ergonomic builder entry points
- agent builders compile static context, dynamic retrieval, tools, and output schemas into concrete agents
- prompt/extractor/streaming request builders run against model traits
- tool servers and streaming use fibers and `Channel` instead of Rust async futures
- vector stores, loaders, and evals are first-class modules rather than example-local helpers

The most important public design choice is that the builder APIs are the primary
surface, not an afterthought. The codebase is structured so examples can read the way
upstream Rig examples read:

- start from a provider client
- choose a model
- configure behavior through chained builders
- call `.build`, `.send`, `.stream`, `.extract`, or `.embed_*`

For a more detailed breakdown, see [`docs/architecture.md`](./docs/architecture.md).

## Development

Install dependencies and run the standard gates:

```bash
make install
make format
make lint
make test
```

Parity manifests live under `plans/inventory/`. The canonical maintenance commands are:

```bash
./scripts/ensure_parity_plan.sh . vendor/rig/rig/rig-core rust auto 0
./scripts/check_port_inventory.sh . plans/inventory/rust_port_inventory.tsv vendor/rig/rig/rig-core rust
./scripts/check_source_parity.sh . plans/inventory/rust_source_parity.tsv vendor/rig/rig/rig-core rust
./scripts/check_test_parity.sh . plans/inventory/rust_test_parity.tsv vendor/rig/rig/rig-core rust
```

## Upstream Relationship

Upstream Rust behavior remains the source of truth for the tracked Rig surface, but
the repository should be read as a Crystal library in its own right.

That means:

- docs should describe the APIs and capabilities that exist in `src/` today
- examples should look like first-class Crystal examples, not temporary parity notes
- the only intentional architectural adaptation is concurrency mechanics:
  Rust uses async/futures, while `crig` uses Crystal fibers and channels

If you are contributing, follow [`AGENTS.md`](./AGENTS.md) and update the parity inventories alongside implementation work.
