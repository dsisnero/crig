require "../../src/crig"

module Crig::Examples::DeepSeekNomicVectorSearch
  # Simplified structure using String API
  struct WordDefinition
    include JSON::Serializable

    getter id : String
    getter word : String
    getter definitions : Array(String)

    def initialize(@id : String, @word : String, @definitions : Array(String))
    end

    # Convert to string for embedding (uses all definitions)
    def to_embedding_text : String
      @definitions.join(" ")
    end

    # Convert to display text
    def to_display_text : String
      "#{@word}: #{@definitions.join("; ")}"
    end
  end

  def self.word_definitions : Array(WordDefinition)
    [
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
      WordDefinition.new(
        "doc3",
        "quantum computer",
        [
          "A computer that uses quantum-mechanical phenomena to perform computation.",
          "Can solve certain problems much faster than classical computers.",
        ]
      ),
      WordDefinition.new(
        "doc4",
        "blockchain",
        [
          "A distributed ledger technology that records transactions across multiple computers.",
          "The technology behind cryptocurrencies like Bitcoin and Ethereum.",
        ]
      ),
    ]
  end

  # Get texts for embedding
  def self.embedding_texts : Array(String)
    word_definitions.map(&.to_embedding_text)
  end

  # Build vector store with Ollama embeddings (free/local)
  def self.build_store(model : M) : Crig::VectorStore::InMemoryVectorIndex(M, WordDefinition) forall M
    # Use the simplified String API for embeddings
    embeddings = Crig::Embeddings.builder(model)
      .documents(embedding_texts)
      .build

    # Create tuples of (WordDefinition, embeddings) for the store
    documents_with_embeddings = embeddings.map_with_index do |(text, embedding), index|
      {word_definitions[index], embedding}
    end

    # Create store with WordDefinition objects
    store = Crig::VectorStore::InMemoryVectorStore(WordDefinition).from_documents_with_id_f(documents_with_embeddings) do |document|
      document.id
    end

    store.index(model)
  end

  # Perform vector search
  def self.search_similar(
    index : Crig::VectorStore::VectorStoreIndex(M, WordDefinition),
    query : String,
    model : M,
    n : Int32 = 3
  ) : Array(Tuple(Float64, String, WordDefinition)) forall M
    # Create embedding for query
    query_embedding = model.embed_text(query)
    
    # Search for similar documents
    request = Crig::VectorSearchRequest.new(
      query: query,
      samples: n.to_u64
    )
    
    index.top_n(request, WordDefinition)
  end

  # Format search results
  def self.format_results(results : Array(Tuple(Float64, String, WordDefinition))) : String
    results.map_with_index do |(score, id, doc), i|
      "Result #{i + 1} (score: #{score.round(3)}):\n" +
      "  Word: #{doc.word}\n" +
      "  Definitions: #{doc.definitions.join("; ")}\n"
    end.join("\n")
  end

  # Example search queries
  def self.example_queries : Array(String)
    [
      "alien life forms",
      "fictional currencies",
      "ancient tools",
      "quantum technology",
      "distributed systems",
      "science fiction concepts",
    ]
  end
end

# Main executable code - always run for examples
begin
  puts "Setting up vector search with DeepSeek + Nomic:"
  puts "  - Embeddings: nomic-embed-text (Ollama, free/local)"
  puts "  - Search: Pure vector similarity (no LLM needed)"
  puts "  - Documents: 5 word/term definitions"
  puts "  - Cost: $0 (completely free, runs locally)"
  puts ""

  # Create Ollama client for embeddings (free/local)
  puts "1. Setting up Ollama for embeddings..."
  ollama_client = Crig::Providers::Ollama::Client.new
  embedding_model = ollama_client.embedding_model("nomic-embed-text")
  puts "   ✓ Using nomic-embed-text (768 dimensions)"

  # Build vector store with Ollama embeddings
  puts "2. Creating vector store with definitions..."
  index = Crig::Examples::DeepSeekNomicVectorSearch.build_store(embedding_model)
  puts "   ✓ Vector store created with #{Crig::Examples::DeepSeekNomicVectorSearch.word_definitions.size} documents"

  # Show what's in the store
  puts "3. Documents in vector store:"
  Crig::Examples::DeepSeekNomicVectorSearch.word_definitions.each do |doc|
    puts "   - #{doc.word}: #{doc.definitions.first[0..50]}..."
  end

  # Run example searches
  puts ""
  puts "4. Running vector similarity searches:"
  puts "=" * 60
  
  Crig::Examples::DeepSeekNomicVectorSearch.example_queries.each do |query|
    puts "\nQuery: \"#{query}\""
    puts "-" * 40
    
    results = Crig::Examples::DeepSeekNomicVectorSearch.search_similar(index, query, embedding_model)
    
    if results.empty?
      puts "No similar documents found."
    else
      puts "Top #{results.size} similar documents:"
      puts Crig::Examples::DeepSeekNomicVectorSearch.format_results(results)
    end
    
    puts "-" * 40
  end

  puts "=" * 60
  puts ""
  puts "Advanced example: Hybrid search with DeepSeek"
  puts "=" * 60
  
  # Check if we have DeepSeek API key for hybrid example
  deepseek_api_key = ENV["DEEPSEEK_API_KEY"]?
  
  if deepseek_api_key
    puts "\n5. Hybrid example: Vector search + LLM summarization"
    puts "   Using DeepSeek to summarize search results"
    puts "-" * 40
    
    # Create DeepSeek client
    deepseek_client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
    agent = deepseek_client.agent(Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
      .preamble("You are a research assistant. Summarize the search results concisely.")
      .temperature(0.3)
      .build
    
    # Search for "future technology"
    query = "future technology"
    puts "Query: \"#{query}\""
    
    results = Crig::Examples::DeepSeekNomicVectorSearch.search_similar(index, query, embedding_model, 2)
    
    if results.empty?
      puts "No results to summarize."
    else
      # Format results for LLM
      context = results.map_with_index do |(score, id, doc), i|
        "Document #{i + 1} (relevance: #{(score * 100).round(1)}%):\n" +
        "Topic: #{doc.word}\n" +
        "Content: #{doc.definitions.join(' ')}"
      end.join("\n\n")
      
      prompt = "Based on these search results about '#{query}', provide a brief summary:\n\n#{context}"
      
      puts "\nSearch results found. Generating summary with DeepSeek..."
      summary = agent.prompt(prompt).send
      puts "\nSummary: #{summary}"
    end
  else
    puts "\n5. Hybrid example (requires DEEPSEEK_API_KEY)"
    puts "   To enable LLM summarization of search results:"
    puts "   export DEEPSEEK_API_KEY=your_deepseek_key"
    puts "   Then run this example again"
  end

  puts "=" * 60
  puts ""
  puts "Summary: This vector search pipeline uses:"
  puts "1. Free local embeddings (Ollama nomic-embed-text)"
  puts "2. Pure vector similarity search (no LLM cost)"
  puts "3. Optional hybrid mode with DeepSeek for summarization"
  puts "4. Multiple related definitions per concept"
  puts ""
  puts "Use cases:"
  puts "• Document retrieval systems"
  puts "• Semantic search engines"
  puts "• Knowledge base lookup"
  puts "• Content recommendation"
  puts ""
  puts "Cost: $0 for pure vector search, ~$0.01 per query with DeepSeek summarization"
rescue ex : IO::Error | Socket::Error
  STDERR.puts "Error: Could not connect to Ollama. Is Ollama running?"
  STDERR.puts "Start Ollama: ollama serve"
  exit 1
rescue ex : Crig::Completion::CompletionError
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts "This could be due to:"
  STDERR.puts "1. Invalid API key"
  STDERR.puts "2. API quota exceeded"
  STDERR.puts "3. Network connectivity issues"
  exit 1
rescue ex
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
  exit 1
end