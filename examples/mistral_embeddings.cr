require "../src/crig"

module Crig::Examples::MistralEmbeddings
  struct Greetings
    include JSON::Serializable
    include Crig::Embeddings::Embed

    getter message : String

    def initialize(@message : String)
    end

    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      embedder.embed(@message)
    end
  end
end

begin
  puts "Setting up embeddings example (Ollama variant):"
  puts "  - Model: nomic-embed-text (Ollama)"
  puts "  - Task: Simple embeddings and vector search"
  puts "  - Documents: Greeting messages"
  puts "  - Cost: Free/local (Ollama)"
  puts ""

  # Initialize the Ollama client
  puts "1. Setting up Ollama client..."
  client = Crig::Providers::Ollama::Client.new
  embedding_model = client.embedding_model("nomic-embed-text")
  puts "   ✓ Ollama client ready"
  puts "   - Model: nomic-embed-text"

  # Create embeddings
  puts "2. Creating embeddings..."
  embeddings = Crig::Embeddings::EmbeddingsBuilder.new(embedding_model)
    .document(Crig::Examples::MistralEmbeddings::Greetings.new("Hello, world!"))
    .document(Crig::Examples::MistralEmbeddings::Greetings.new("Goodbye, world!"))
    .build

  puts "   ✓ Created #{embeddings.size} embeddings"

  # Create vector store with the embeddings
  puts "3. Creating vector store..."
  vector_store = Crig::VectorStore::InMemoryVectorStore(Crig::Examples::MistralEmbeddings::Greetings).from_documents(embeddings)

  # Create vector store index
  index = vector_store.index(embedding_model)
  puts "   ✓ Vector store index created"

  # Perform vector search
  puts ""
  puts "4. Performing vector search:"
  puts "=" * 60

  query = "Hello world"
  puts "Query: \"#{query}\""
  puts ""

  req = Crig::VectorSearchRequest.new(
    query: query,
    samples: 1
  )

  puts "Searching for similar documents..."
  results = index.top_n(req, Crig::Examples::MistralEmbeddings::Greetings)

  puts "Results:"
  results.each do |score, id, greeting|
    puts "  Score: #{score.round(4)}, ID: #{id}, Message: #{greeting.message}"
  end

  puts "=" * 60
  puts ""
  puts "Summary: This example shows simple embeddings with Ollama:"
  puts "1. Create embeddable structs with the Embed mixin"
  puts "2. Generate embeddings using Ollama (free/local)"
  puts "3. Store embeddings in an in-memory vector store"
  puts "4. Perform similarity search"
  puts ""
  puts "Note: This example requires Ollama with the nomic-embed-text model:"
  puts "  ollama pull nomic-embed-text"
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
