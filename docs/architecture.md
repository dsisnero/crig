# Architecture

`crig` is a Crystal implementation of Rig's `rig-core` architecture, not just a loose
wrapper around provider HTTP calls. The codebase keeps the same major subsystem
boundaries as upstream and preserves the same public workflows where possible.

## Source of Truth

- Upstream repository: `https://github.com/0xPlaygrounds/rig.git`
- Pinned checkout: `vendor/rig`
- Target crate: `vendor/rig/rig/rig-core`
- Pinned baseline commit: `06bc651f4c64d1673ba6af698f6c66602c5d313f`

Rust source, tests, and fixtures define the expected behavior for tracked parity
work. Crystal adaptations are acceptable only where the languages differ
structurally, with concurrency being the main approved example.

## Directory Map

```
src/
├── crig.cr                         # Entry point — requires all subsystems, defines Crig module + version/upstream constants
│
├── crig/
│   ├── agent.cr                    # Agent + AgentBuilder — the largest module (737 lines). Combines model, preamble,
│   │                                #   tools (static/dynamic/MCP), output schemas, memory, hooks. Agent.runner
│   │                                #   orchestrates the prompt→tool-call→completion loop.
│   │
│   ├── agent/                      # Agent runtime internals
│   │   ├── completion.cr           #   Completion request execution for agents
│   │   ├── streaming.cr            #   Streaming support for agent prompts
│   │   ├── hook.cr                 #   Demotion hooks (intercept tool failures)
│   │   ├── run.cr                  #   Synchronous run loop
│   │   ├── run/streamed.cr         #   Streamed (channel-based) run loop
│   │   ├── runner.cr               #   Top-level agent entry point
│   │   ├── prompt_request.cr       #   Prompt request builder
│   │   └── prompt_request/         #   Streamed prompt request builder
│   │       └── streaming.cr
│   │
│   ├── client.cr                   # Client type alias hub — re-exports CompletionClient, EmbeddingsClient,
│   │                                #   ImageGenerationClient, etc. as single `Client` namespace
│   │
│   ├── client/                     # Client implementations per capability (model → builder wiring)
│   │   ├── base.cr                 #   Shared client base
│   │   ├── builder.cr              #   Client builder (DynClientBuilder)
│   │   ├── completion.cr           #   Completion client wiring
│   │   ├── embeddings.cr           #   Embeddings client wiring
│   │   ├── image_generation.cr     #   Image generation client wiring
│   │   ├── audio_generation.cr     #   Audio generation client wiring
│   │   ├── transcription.cr        #   Transcription client wiring
│   │   ├── model_listing.cr        #   Model listing client wiring
│   │   └── verify.cr               #   API key verification client wiring
│   │
│   ├── completion.cr               # Completion pipeline — types for chat messages, roles, request builders
│   ├── completion/
│   │   ├── message.cr              #   Message structs (system, user, assistant, tool)
│   │   └── request.cr              #   CompletionRequest builder
│   │
│   ├── streaming.cr                # Streaming types — StreamingCompletionResponse, choice aggregation,
│   │                                #   pause/resume/cancel, final-response handling
│   ├── streaming_traits.cr         # Streaming response traits for provider implementations
│   │
│   ├── providers.cr                # Providers module namespace — dispatches to 25+ provider shards
│   ├── providers/                  # One subdirectory per provider (or flat file for simple ones)
│   │   ├── openai/                 #   OpenAI: chat completions, embeddings, image gen, audio gen,
│   │   │                                #     transcription, model listing, Responses API (+ streaming + WebSocket)
│   │   ├── anthropic/              #   Anthropic Claude: completion, streaming, model listing, SSE decoders
│   │   ├── gemini/                 #   Gemini: completion, streaming, embedding, transcription,
│   │   │                                #     Interactions API (+ streaming), model listing
│   │   ├── cohere/                 #   Cohere: completion, streaming, embedding
│   │   ├── mistral/                #   Mistral: completion, streaming, embedding, transcription, model listing
│   │   ├── openrouter/             #   OpenRouter: completion, streaming, embedding, audio gen, transcription,
│   │   │                                #     model listing
│   │   ├── xai/                    #   xAI/Grok: completion, streaming, image gen, audio gen
│   │   ├── huggingface/            #   HuggingFace: completion, image gen, transcription
│   │   ├── together/               #   Together: completion, streaming, embedding
│   │   ├── perplexity/             #   Perplexity: completion, streaming
│   │   ├── chatgpt/                #   ChatGPT: completion, OAuth
│   │   ├── copilot/                #   GitHub Copilot: completion, OAuth
│   │   ├── deepseek.cr             #   DeepSeek (flat file)
│   │   ├── groq.cr                 #   Groq (flat file)
│   │   ├── ollama.cr               #   Ollama (flat file)
│   │   ├── azure.cr                #   Azure OpenAI (flat file)
│   │   ├── hyperbolic.cr           #   Hyperbolic (flat file)
│   │   ├── llamafile.cr            #   Llamafile (flat file)
│   │   ├── minimax.cr, mira.cr     #   MiniMax, Mira (flat files)
│   │   ├── moonshot.cr             #   Moonshot (flat file)
│   │   ├── voyageai.cr             #   VoyageAI embedding (flat file)
│   │   ├── zai.cr, xiaomimimo.cr   #   Zai, Xiaomimimo (flat files)
│   │   ├── galadriel.cr            #   Galadriel (flat file)
│   │   └── internal/               #   OpenAI chat completions compatible adapter
│   │
│   ├── tool.cr                     # Tool system — Tool (interface), ToolSet, ToolMacro, ToolDyn,
│   │                                #   ToolError, ToolSetBuilder (517 lines)
│   ├── tool/
│   │   ├── extensions.cr           #   Tool definition extensions
│   │   ├── result.cr               #   ToolResult type
│   │   ├── server.cr               #   ToolServer — runtime coordinator for agent tool execution
│   │   └── rmcp.cr                 #   MCP/RMCP-backed tool server (stdio, SSE, streamable HTTP)
│   │
│   ├── tools/
│   │   └── think.cr                # Built-in "think" tool
│   │
│   ├── embeddings.cr               # Embeddings interface — EmbeddingModel, EmbeddingBuilder
│   ├── embeddings/
│   │   ├── embedding.cr            #   Embedding struct
│   │   ├── builder.cr              #   EmbeddingsBuilder — accumulates docs, batches API calls
│   │   ├── distance.cr             #   Cosine similarity / vector distance
│   │   └── tool.cr                 #   Embedding-backed tool definitions
│   │
│   ├── vector_store.cr             # Vector store interface
│   ├── vector_store/
│   │   ├── request.cr              #   VectorSearchRequest builder
│   │   ├── builder.cr              #   InMemoryVectorStoreBuilder
│   │   ├── in_memory_store.cr      #   InMemoryVectorStore — brute-force + LSH-backed search
│   │   ├── lsh.cr                  #   LSH index (locality-sensitive hashing)
│   │   └── vectorize.cr            #   Vectorize helper
│   │
│   ├── extractor.cr                # Structured extraction — uses submit-tool strategy (same as upstream)
│   ├── evals.cr                    # LLM-as-judge evaluation — LlmJudgeMetric, SemanticSimilarityMetric
│   ├── rerank.cr                   # Reranking — RerankModel interface
│   │
│   ├── http_client.cr              # HTTP transport layer — send, send_streaming, error handling
│   ├── http_client/
│   │   ├── sse.cr                  #   Server-Sent Events parser
│   │   ├── retry.cr                #   Retry logic
│   │   └── multipart.cr            #   Multipart form uploads
│   │
│   ├── loaders.cr                  # Document loader interface
│   ├── loaders/
│   │   ├── file.cr                 #   File loader
│   │   ├── pdf.cr                  #   PDF loader
│   │   └── epub/                   #   EPUB loader (loader.cr, errors.cr, text_processors.cr)
│   │
│   ├── memory.cr                   # Conversation memory interface + InMemoryConversationMemory
│   ├── memory/
│   │   └── policies.cr             #   Memory compaction policies
│   │
│   ├── audio_generation.cr         # Audio generation interface
│   ├── image_generation.cr         # Image generation interface
│   ├── transcription.cr            # Transcription interface
│   ├── model.cr                    # Model + ModelListing interfaces
│   ├── model/
│   │   └── listing.cr              #   Model listing types
│   │
│   ├── provider_response.cr        # Provider response parsing
│   ├── concurrency.cr              # Concurrency primitives — Result, channel-backed async helpers
│   ├── telemetry.cr                # OpenTelemetry tracing — Span, ProviderRequestExt, ProviderResponseExt
│   │
│   ├── json_utils.cr               # JSON parsing helpers
│   ├── id.cr                       # ID generation (hex)
│   ├── one_or_many.cr              # OneOrMany collection wrapper
│   ├── markers.cr                  # Telemetry attribute constants (GEN_AI_*)
│   └── wasm_compat.cr              # WASM compatibility shims
│
└── crig/
    └── integrations/               # First-class integrations
        ├── cli_chatbot.cr          #   CLI chatbot loop
        └── discord_bot.cr          #   Discord bot
```

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
- MCP / RMCP-backed tool servers (stdio, SSE, and streamable HTTP transports)
- SQLite and PostgreSQL vector-store examples

These are real integration surfaces, not placeholder directories. The README should
therefore describe them as part of the shipped library surface whenever they are
implemented in `src/`.

## Documentation Rule

Top-level docs should describe what exists in the current Crystal codebase.

That means:

- do not reduce the repo description to "this is a port"
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
