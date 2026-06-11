# crig

`crig` is a Crystal library for building modular, builder-first LLM applications.

It ports the public behavior of [Rig](https://github.com/0xPlaygrounds/rig)'s
`rig-core` crate into Crystal. The codebase includes agents, extractors, provider
clients, embeddings, vector stores, streaming, tool servers, CLI/Discord
integrations, and 100+ ported examples.

Current upstream parity source:
- Repository: `https://github.com/0xPlaygrounds/rig.git`
- Submodule path: `vendor/rig`
- Rust crate under port: `vendor/rig/crates/rig-core`
- Pinned upstream commit: `f77a5819ec2a71e98583480a68a341f816a75c8a`

- [What is crig?](#what-is-crig)
- [Features](#features)
- [Get Started](#get-started)
  - [Simple agent](#simple-agent)
  - [Structured extraction](#structured-extraction)
  - [Streaming](#streaming)
- [Providers](#providers)
- [Examples](#examples)
- [Architecture](#architecture)
- [Development](#development)
- [Upstream Relationship](#upstream-relationship)

## What is crig?

`crig` gives Crystal applications a unified, builder-first interface for:

- completion, chat, and streaming across 25+ providers
- agent workflows with tools, dynamic context, memory, and multi-turn prompting
- structured extraction
- embeddings, vector stores, and RAG pipelines
- tool servers (local and MCP)
- transcription, audio generation, and image generation

Every workflow starts from a provider client and branches through ergonomic builders:

- `client.agent(model)` — build an agent with preamble, tools, and context
- `client.extractor(Type, model)` — structured data extraction
- `client.embeddings(model)` — embeddings for search and RAG
- `model.completion_request(prompt)` — raw completion building
- `model.stream(prompt)` — streaming responses via channels

## Features

- 25+ providers under a unified client/model abstraction
- Agent workflows: static context, dynamic (RAG) context, tools, tool servers, memory, multi-turn prompting with hooks
- Streaming via Crystal channels instead of async futures
- Structured extraction using the same submit-tool strategy as upstream Rig
- Embeddings builders, in-memory vector stores, vector search with distance metrics
- Tool definitions, embedding-backed tools, MCP tools, concurrent tool-server execution
- Transcription, audio generation, and image generation
- 100+ ported examples covering agents, extractors, streaming, RAG, and every provider

## Get Started

Add `crig` to your `shard.yml`:

```yaml
dependencies:
  crig:
    github: dsisnero/crig
```

```bash
shards install
```

Set your provider API key (here OpenAI):

```bash
export OPENAI_API_KEY="sk-..."
```

### Simple agent

```crystal
require "crig"

client = Crig::Providers::OpenAI::Client.from_env

agent = client
  .agent(Crig::Providers::OpenAI::GPT_5_2)
  .preamble("You are a helpful assistant.")
  .build

puts agent.prompt("What can you tell me about Crystal?").send
```

### Defining tools

```crystal
# Minimal: auto-generated schema from parameter types
Crig.rig_tool do
  def echo(text : String) : String
    text
  end
end

# With description and optional params
Crig.rig_tool description: "Greet someone" do
  def greet(name : String, style : String?) : String
    "#{style || "Hello"}, #{name}"
  end
end

# With error handling via Result
Crig.rig_tool description: "Divide two numbers" do
  def divide(x : Int32, y : Int32) : Crig::ToolMacro::Result(Int32, Crig::ToolError)
    if y == 0
      Crig::ToolMacro::Result(Int32, Crig::ToolError).err(Crig::ToolError.new("Division by zero"))
    else
      Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x // y)
    end
  end
end

# Use with an agent
agent = client
  .agent(Crig::Providers::OpenAI::GPT_5_2)
  .preamble("You are a calculator.")
  .tool(Calculator.new)
  .build
```

### Structured extraction

```crystal
require "crig"

struct Sentiment
  include JSON::Serializable
  getter sentiment : String
  getter confidence : Float64
end

client = Crig::Providers::OpenAI::Client.from_env

extractor = client
  .extractor(Sentiment, Crig::Providers::OpenAI::GPT_4O_MINI)
  .build

result = extractor.extract("I absolutely love this library!")
# => ExtractionResponse(@output=Sentiment(@sentiment="positive", @confidence=0.95))
```

### Streaming

```crystal
require "crig"

client = Crig::Providers::Anthropic::Client.from_env

model = client.completion_model(Crig::Providers::Anthropic::CLAUDE_SONNET_4_6)

model.stream("Write a haiku about programming.").each_item do |item|
  print item.text.try(&.text) if item.kind.text?
end
puts
```

## Providers

25 providers under `src/crig/providers/`, all accessed through the same builder API:

| Provider | Completion | Streaming | Embeddings | Transcription | Image Gen | Audio Gen |
|---|---|---|---|---|---|---|
| Anthropic | ✓ | ✓ | — | — | — | — |
| Azure OpenAI | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| ChatGPT | ✓ | ✓ | — | — | — | — |
| Cohere | ✓ | ✓ | ✓ | — | — | — |
| Copilot | ✓ | — | ✓ | — | — | — |
| DeepSeek | ✓ | ✓ | — | — | — | — |
| Galadriel | ✓ | ✓ | — | — | — | — |
| Gemini | ✓ | ✓ | ✓ | ✓ | — | — |
| Groq | ✓ | ✓ | — | — | — | — |
| Hugging Face | ✓ | ✓ | — | ✓ | ✓ | — |
| Hyperbolic | ✓ | ✓ | — | — | ✓ | ✓ |
| Llamafile | ✓ | ✓ | — | — | — | — |
| MiniMax | ✓ | ✓ | — | — | — | — |
| Mira | ✓ | ✓ | — | — | — | — |
| Mistral | ✓ | ✓ | ✓ | ✓ | — | — |
| Moonshot | ✓ | ✓ | — | — | — | — |
| Ollama | ✓ | ✓ | ✓ | — | — | — |
| OpenAI | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| OpenRouter | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| Perplexity | ✓ | ✓ | — | — | — | — |
| Together | ✓ | ✓ | ✓ | — | — | — |
| VoyageAI | — | — | ✓ | — | — | — |
| xAI | ✓ | ✓ | — | — | — | — |
| XiaomiMimo | ✓ | ✓ | — | — | — | — |
| ZAI | ✓ | ✓ | — | — | — | — |

Integration modules also exist for:
- CLI chatbots (`Crig::Integrations::CliChatbot`)
- Discord bots (`Crig::Integrations::DiscordBot`)
- MCP / RMCP tool servers (`Crig::Tool::Server`)
- Conversation memory (`Crig::Memory`)
- Telemetry / OpenTelemetry spans

## Examples

100+ ported examples live under [`examples/`](./examples). A few highlights:

| Example | What it shows |
|---|---|
| [`examples/agent.cr`](./examples/agent.cr) | Basic agent with preamble and prompt |
| [`examples/agent_with_tools.cr`](./examples/agent_with_tools.cr) | Agent with custom tool definitions |
| [`examples/extractor.cr`](./examples/extractor.cr) | Structured data extraction from text |
| [`examples/rag.cr`](./examples/rag.cr) | Retrieval-augmented generation pipeline |
| [`examples/multi_turn_agent.cr`](./examples/multi_turn_agent.cr) | Multi-turn agent conversation |
| [`examples/openai_streaming.cr`](./examples/openai_streaming.cr) | Token-by-token streaming with OpenAI |
| [`examples/anthropic_streaming_with_tools.cr`](./examples/anthropic_streaming_with_tools.cr) | Anthropic streaming with tool calls |
| [`examples/gemini_extractor_with_rag.cr`](./examples/gemini_extractor_with_rag.cr) | Gemini extraction with RAG context |
| [`examples/rmcp.cr`](./examples/rmcp.cr) | MCP tool server integration |
| [`examples/discord_bot.cr`](./examples/discord_bot.cr) | Discord bot with agent backend |
| [`examples/calculator_chatbot.cr`](./examples/calculator_chatbot.cr) | Interactive CLI chatbot |
| [`examples/multi_agent.cr`](./examples/multi_agent.cr) | Multi-agent orchestration |
| [`examples/vector_search.cr`](./examples/vector_search.cr) | Vector search with in-memory store |
| [`examples/loaders.cr`](./examples/loaders.cr) | File, PDF, and EPUB document loaders |
| [`examples/request_hook.cr`](./examples/request_hook.cr) | Prompt and tool-call hooks |
| [`examples/transcription.cr`](./examples/transcription.cr) | Audio transcription workflow |
| [`examples/openai_image_generation.cr`](./examples/openai_image_generation.cr) | Image generation with DALL·E |
| [`examples/sentiment_classifier.cr`](./examples/sentiment_classifier.cr) | LLM-based sentiment evaluation |

## Architecture

`crig` follows `rig-core`'s decomposition with Crystal-native execution:

- **`src/crig/client/`** — generic client infrastructure, provider builder traits, dyn-client factory
- **`src/crig/completion/`** — message types, completion request/response, chat traits
- **`src/crig/agent/`** — agent builder, prompt requests, streaming multi-turn loop, hooks
- **`src/crig/embeddings/`** — embedding model traits, builders, distance metrics, vector stores
- **`src/crig/providers/`** — 25 provider implementations with request/response conversion
- **`src/crig/tool/`** — tool definitions, tool servers, MCP integration
- **`src/crig/pipeline/`** — composable pipeline ops (map, then, chain, parallel, try)
- **`src/crig/loaders/`** — file, PDF, and EPUB document loaders
- **`src/crig/evals.cr`** — LLM-as-judge evaluation metrics
- **`src/crig/memory.cr`** — conversation memory traits and in-memory backend

The builder API is the primary surface — every workflow starts from a client, chains
builder calls, and terminates with `.build`, `.send`, `.stream`, or `.extract`.
Crystal fibers and `Channel` replace Rust's async/futures for concurrency.

## Development

```bash
make install        # install dependencies
make format         # crystal tool format --check
make lint           # ameba
make test           # crystal spec
```

Parity tracking lives under `plans/inventory/`. Bootstrap and validate:

```bash
./scripts/ensure_parity_plan.sh . vendor/rig/crates/rig-core rust auto 0
./scripts/check_port_inventory.sh . plans/inventory/rust_port_inventory.tsv vendor/rig/crates/rig-core rust
./scripts/check_source_parity.sh . plans/inventory/rust_source_parity.tsv vendor/rig/crates/rig-core rust
./scripts/check_test_parity.sh . plans/inventory/rust_test_parity.tsv vendor/rig/crates/rig-core rust
```

Current parity: 2,500 source items ported, 249 intentional divergences, 0 missing.
Source parity tracks 2,155 API items; test parity tracks 507 upstream test equivalents.

## Upstream Relationship

Upstream Rust behavior remains the source of truth for the tracked Rig surface, but
the repository should be read as a Crystal library in its own right.

That means:

- docs should describe the APIs and capabilities that exist in `src/` today
- examples should look like first-class Crystal examples, not temporary parity notes
- the only intentional architectural adaptation is concurrency mechanics:
  Rust uses async/futures, while `crig` uses Crystal fibers and channels

If you are contributing, follow [`AGENTS.md`](./AGENTS.md) and update the parity inventories alongside implementation work.
