require "../src/crig"

module Crig::Examples::RagOllama
  struct WordDefinition
    include JSON::Serializable
    include Crig::Embeddings::Embed

    getter id : String
    getter word : String
    getter definitions : Array(String)

    def initialize(@id : String, @word : String, @definitions : Array(String))
    end

    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      @definitions.each do |definition|
        embedder.embed(definition)
      end
    end
  end
end

begin
  puts "Setting up RAG with Ollama example:"
  puts "  - Model: nomic-embed-text (embeddings)"
  puts "  - Task: RAG for word definitions"
  puts "  - Method: Dynamic context retrieval"
  puts "  - Cost: Free/local (Ollama)"
  puts ""

  # Create Ollama client
  puts "1. Setting up Ollama client..."
  ollama_client = Crig::Providers::Ollama::Client.new(Crig::Nothing.new, "http://localhost:11434")
  puts "   ✓ Ollama client ready"

  embedding_model = ollama_client.embedding_model("nomic-embed-text")
  puts "   ✓ Using nomic-embed-text embedding model"

  # Create word definitions
  puts "3. Creating word definitions database..."
  word_definitions = [
    Crig::Examples::RagOllama::WordDefinition.new(
      id: "doc0",
      word: "flurbo",
      definitions: [
        "1. *flurbo* (name): A flurbo is a green alien that lives on cold planets.",
        "2. *flurbo* (name): A fictional digital currency that originated in the animated series Rick and Morty.",
      ]
    ),
    Crig::Examples::RagOllama::WordDefinition.new(
      id: "doc1",
      word: "glarb-glarb",
      definitions: [
        "1. *glarb-glarb* (noun): A glarb-glarb is a ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land.",
        "2. *glarb-glarb* (noun): A fictional creature found in the distant, swampy marshlands of the planet Glibbo in the Andromeda galaxy.",
      ]
    ),
    Crig::Examples::RagOllama::WordDefinition.new(
      id: "doc2",
      word: "zibble",
      definitions: [
        "1. *zibble* (verb): To zibble means to move in a zigzag pattern while making a high-pitched humming sound.",
        "2. *zibble* (noun): A zibble is a unit of measurement equivalent to approximately 3.7 flurbos.",
      ]
    ),
  ]

  puts "   ✓ Created #{word_definitions.size} word definitions"

  # Generate embeddings for the definitions
  puts "4. Generating embeddings..."

  # Create embeddings using the EmbeddingsBuilder with WordDefinition documents
  embeddings = Crig::Embeddings::EmbeddingsBuilder(typeof(embedding_model), Crig::Examples::RagOllama::WordDefinition)
    .new(embedding_model)
    .documents(word_definitions)
    .build

  puts "   ✓ Generated #{embeddings.size} embeddings"

  # Create vector store with the embeddings
  vector_store = Crig::VectorStore::InMemoryVectorStore(Crig::Examples::RagOllama::WordDefinition).from_documents(embeddings)

  # Create vector store index
  index = vector_store.index(embedding_model)
  puts "   ✓ Vector store index created"

  # Create RAG agent with dynamic context (using Ollama for completions too)
  puts "6. Creating RAG agent with dynamic context..."
  completion_model = ollama_client.completion_model("qwen2.5:14b")
  rag_agent = ollama_client.agent("qwen2.5:14b")
    .preamble(<<-PROMPT
        You are a dictionary assistant here to assist the user in understanding the meaning of words.
        You will find additional non-standard word definitions that could be useful below.
        PROMPT
    )
    .dynamic_context(1, index)
    .build

  puts "   ✓ RAG agent ready"
  puts "   - Embedding model: nomic-embed-text"
  puts "   - Completion model: qwen2.5:14b"
  puts "   - Context documents: 1 (top match)"

  puts ""
  puts "7. Testing RAG agent with query:"
  puts "=" * 60

  # Test query matching Rust example
  query = "What does \"glarb-glarb\" mean?"
  puts "Query: \"#{query}\""
  puts ""

  puts "Agent response:"
  puts "-" * 40

  response = rag_agent.prompt(query)
  puts response
  puts "-" * 40

  puts "=" * 60
  puts ""
  puts "Summary: This example shows RAG (Retrieval-Augmented Generation) with Ollama."
  puts "Key components:"
  puts "1. Word definitions with embeddable fields"
  puts "2. Ollama embeddings (nomic-embed-text)"
  puts "3. Vector store for similarity search"
  puts "4. RAG agent with dynamic context retrieval"
  puts "5. Ollama completion model (qwen2.5:14b)"
  puts ""
  puts "Note: This example requires Ollama with both models:"
  puts "  ollama pull nomic-embed-text"
  puts "  ollama pull qwen2.5:14b"
rescue ex : Socket::ConnectError
  STDERR.puts "Error: Cannot connect to Ollama at http://localhost:11434"
  STDERR.puts "Please ensure Ollama is running: ollama serve"
  STDERR.puts "And pull the nomic-embed-text model: ollama pull nomic-embed-text"
  exit 1
rescue ex : Crig::Embeddings::EmbedError
  STDERR.puts "Embedding error: #{ex.message}"
  STDERR.puts "This could be due to:"
  STDERR.puts "1. Model not available (run: ollama pull nomic-embed-text)"
  STDERR.puts "2. Ollama service issues"
  exit 1
rescue ex
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
  exit 1
end
