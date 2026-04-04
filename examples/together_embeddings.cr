require "../src/crig"

module Crig::Examples::TogetherEmbeddings
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
  puts "Setting up Together Embeddings example (Ollama variant):"
  puts "  - Model: Ollama nomic-embed-text"
  puts "  - Feature: Embedding generation"
  puts "  - Task: Embed greeting messages"
  puts "  - Cost: Free (local Ollama)"
  puts ""

  # Initialize the Ollama client
  puts "1. Setting up Ollama client..."
  client = Crig::Providers::Ollama::Client.new
  embedding_model = client.embedding_model("nomic-embed-text")
  puts "   ✓ Ollama client ready"
  puts "   - Model: nomic-embed-text"

  # Create embeddings
  puts "2. Creating embeddings for greeting messages..."
  embeddings = Crig::Embeddings::EmbeddingsBuilder.new(embedding_model)
    .document(Crig::Examples::TogetherEmbeddings::Greetings.new("Hello, world!"))
    .document(Crig::Examples::TogetherEmbeddings::Greetings.new("Goodbye, world!"))
    .build

  puts "   ✓ Created #{embeddings.size} embeddings"

  # Create vector store with the embeddings
  puts "3. Creating vector store..."
  vector_store = Crig::VectorStore::InMemoryVectorStore(Crig::Examples::TogetherEmbeddings::Greetings).from_documents(embeddings)

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
    samples: 2
  )

  results = index.top_n(req, Crig::Examples::TogetherEmbeddings::Greetings).to_a
  puts "Top #{results.size} results:"
  results.each do |score, id, doc|
    puts "  [#{score.round(4)}] #{id}: #{doc.message}"
  end

  puts "Summary: This example demonstrates embedding generation using Ollama's nomic-embed-text model."
  puts "The Embed macro automatically extracts text from annotated fields in the Greetings struct."
  puts "Use cases for embeddings:"
  puts "• Semantic search and retrieval"
  puts "• Document clustering and classification"
  puts "• Similarity matching"
  puts "• RAG (Retrieval Augmented Generation) pipelines"
rescue ex : KeyError
  STDERR.puts "Error: Missing API key or configuration"
  STDERR.puts "Please ensure Ollama is running locally or set OLLAMA_BASE_URL"
  exit 1
rescue ex : Crig::Embeddings::EmbeddingError
  STDERR.puts "Embedding error: #{ex.message}"
  STDERR.puts "This could be due to:"
  STDERR.puts "1. Ollama not running locally"
  STDERR.puts "2. nomic-embed-text model not pulled (run: ollama pull nomic-embed-text)"
  STDERR.puts "3. Network connectivity issues"
  exit 1
rescue ex
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
  exit 1
end
