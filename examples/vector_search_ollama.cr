require "../src/crig"

module Crig::Examples::VectorSearchOllama
  # Shape of data that needs to be RAG'ed.
  # The definition field will be used to generate embeddings.
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

  def self.run
    begin
      puts "Setting up vector search with Ollama example:"
      puts "  - Embeddings: nomic-embed-text (Ollama)"
      puts "  - Task: Pure vector similarity search"
      puts "  - Documents: Word definitions"
      puts "  - Cost: Free/local (Ollama)"
      puts ""

      # Create ollama client
      puts "1. Setting up Ollama client..."
      client = Crig::Providers::Ollama::Client.new
      puts "   ✓ Ollama client ready"

      embedding_model = client.embedding_model("nomic-embed-text")
      puts "   ✓ Using nomic-embed-text embedding model"

      # Create word definitions
      puts "2. Creating word definitions..."
      word_definitions = [
        WordDefinition.new(
          "doc0",
          "flurbo",
          [
            "A green alien that lives on cold planets.",
            "A fictional digital currency that originated in the animated series Rick and Morty.",
          ]
        ),
        WordDefinition.new(
          "doc1",
          "glarb-glarb",
          [
            "An ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land.",
            "A fictional creature found in the distant, swampy marshlands of the planet Glibbo in the Andromeda galaxy.",
          ]
        ),
        WordDefinition.new(
          "doc2",
          "linglingdong",
          [
            "A term used by inhabitants of the sombrero galaxy to describe humans.",
            "A rare, mystical instrument crafted by the ancient monks of the Nebulon Mountain Ranges on the planet Quarm.",
          ]
        ),
      ]

      puts "   ✓ Created #{word_definitions.size} word definitions"

      # Generate embeddings for the definitions
      puts "3. Generating embeddings..."

      # Create embeddings using the EmbeddingsBuilder with WordDefinition documents
      embeddings = Crig::Embeddings::EmbeddingsBuilder.new(embedding_model)
        .documents(word_definitions)
        .build

      puts "   ✓ Generated #{embeddings.size} embeddings"

      # Create vector store with the embeddings
      puts "4. Creating vector store..."

      # Create vector store from embeddings with WordDefinition documents
      vector_store = Crig::VectorStore::InMemoryVectorStore(WordDefinition).from_documents_with_id_f(
        embeddings
      ) do |document|
        document.id
      end

      # Create vector store index
      index = vector_store.index(embedding_model)
      puts "   ✓ Vector store index created"

      # Perform vector search
      puts ""
      puts "5. Performing vector search:"
      puts "=" * 60

      query = "I need to buy something in a fictional universe. What type of money can I use for this?"
      puts "Query: \"#{query}\""
      puts ""

      # Create search request
      request = Crig::VectorSearchRequest.new(
        query: query,
        samples: 1
      )

      # Get full results with WordDefinition objects
      puts "Searching for similar documents..."
      results = index.top_n(request, WordDefinition)

      puts "Results (score, id, word):"
      results.each do |score, id, doc|
        puts "  Score: #{score.round(4)}, ID: #{id}, Word: #{doc.word}"
        puts "  Definitions:"
        doc.definitions.each_with_index do |defn, i|
          puts "    #{i + 1}. #{defn}"
        end
      end

      # Get just IDs
      puts ""
      puts "ID results (score, id):"
      id_results = index.top_n_ids(request)
      id_results.each do |score, id|
        puts "  Score: #{score.round(4)}, ID: #{id}"
      end

      puts "=" * 60
      puts ""
      puts "Summary: This example shows pure vector similarity search with Ollama."
      puts "Key components:"
      puts "1. Word definitions with embeddable fields"
      puts "2. Ollama embeddings (nomic-embed-text)"
      puts "3. Vector store for similarity search"
      puts "4. Two search methods: full documents and just IDs"
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
  end

  # Main executable code - only run when file is executed directly
  if PROGRAM_NAME == __FILE__
    Crig::Examples::VectorSearchOllama.run
  end
end
