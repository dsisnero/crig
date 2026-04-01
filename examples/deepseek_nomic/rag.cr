require "../../src/crig"

module Crig::Examples::DeepSeekNomicRag
  # Simplified structure using String API (no custom Embed struct needed)
  struct WordDefinition
    include JSON::Serializable

    getter id : String
    getter word : String
    getter definitions : Array(String)

    def initialize(@id : String, @word : String, @definitions : Array(String))
    end

    # Convert to string for embedding (uses first definition)
    def to_embedding_text : String
      @definitions.first? || ""
    end

    # Convert to display text
    def to_display_text : String
      "#{@word}:\n#{@definitions.map { |d| "  • #{d}" }.join("\n")}"
    end
  end

  PREAMBLE = <<-TEXT
            You are a dictionary assistant here to assist the user in understanding the meaning of words.
            You will find additional non-standard word definitions that could be useful below.
            Use the provided definitions to answer questions about word meanings.
  TEXT

  def self.word_definitions : Array(WordDefinition)
    [
      WordDefinition.new(
        "doc0",
        "flurbo",
        [
          "1. *flurbo* (name): A flurbo is a green alien that lives on cold planets.",
          "2. *flurbo* (name): A fictional digital currency that originated in the animated series Rick and Morty.",
        ]
      ),
      WordDefinition.new(
        "doc1",
        "glarb-glarb",
        [
          "1. *glarb-glarb* (noun): A glarb-glarb is a ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land.",
          "2. *glarb-glarb* (noun): A fictional creature found in the distant, swampy marshlands of the planet Glibbo in the Andromeda galaxy.",
        ]
      ),
      WordDefinition.new(
        "doc2",
        "linglingdong",
        [
          "1. *linglingdong* (noun): A term used by inhabitants of the far side of the moon to describe humans.",
          "2. *linglingdong* (noun): A rare, mystical instrument crafted by the ancient monks of the Nebulon Mountain Ranges on the planet Quarm.",
        ]
      ),
    ]
  end

  # Get texts for embedding (using first definition of each word)
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

  # Build agent with DeepSeek (low-cost cloud API)
  def self.build_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.3)  # Lower temperature for factual responses
      .build
  end

  # Build RAG pipeline
  def self.build_chain(index, agent)
    Crig.pipeline
      .chain(
        Crig.parallel!(
          Crig.passthrough,
          Crig.pipeline.lookup(index, 2, WordDefinition),  # Get top 2 matches
        )
      )
      .map do |(prompt, maybe_docs)|
        if error = maybe_docs.error
          "Error: #{error}! Prompting without additional context\n\n#{prompt}"
        else
          docs = maybe_docs.value || [] of Tuple(Float64, String, WordDefinition)
          if docs.empty?
            "No relevant definitions found. Using general knowledge:\n\n#{prompt}"
          else
            context = docs.map(&.[2].to_display_text).join("\n\n")
            "Relevant word definitions:\n#{context}\n\nQuestion: #{prompt}\n\nAnswer based on the definitions above:"
          end
        end
      end
      .prompt(agent)
  end

  # Example prompts
  def self.example_prompts : Array(String)
    [
      "What is a flurbo?",
      "Tell me about glarb-glarb",
      "What does linglingdong mean?",
      "Compare flurbo and glarb-glarb",
      "Are these real words or fictional?",
    ]
  end
end

# Main executable code - always run for examples
begin
  # Check if DEEPSEEK_API_KEY is set
  deepseek_api_key = ENV["DEEPSEEK_API_KEY"]?

  if deepseek_api_key
    puts "Setting up hybrid RAG pipeline with DeepSeek + Nomic:"
    puts "  - Embeddings: nomic-embed-text (Ollama, free/local)"
    puts "  - Completions: DeepSeek Chat (cloud API, ~10x cheaper than OpenAI)"
    puts "  - Documents: 3 word definitions with multiple meanings each"
    puts "  - Cost: ~$0.12 per 1M tokens (vs $2.63 for OpenAI)"
    puts ""

    # Create Ollama client for embeddings (free/local)
    puts "1. Setting up Ollama for embeddings..."
    ollama_client = Crig::Providers::Ollama::Client.new
    embedding_model = ollama_client.embedding_model("nomic-embed-text")
    puts "   ✓ Using nomic-embed-text (768 dimensions)"

    # Build vector store with Ollama embeddings
    puts "2. Creating vector store with word definitions..."
    store = Crig::Examples::DeepSeekNomicRag.build_store(embedding_model)
    puts "   ✓ Vector store created with #{Crig::Examples::DeepSeekNomicRag.word_definitions.size} documents"

    # Create DeepSeek client for completions
    puts "3. Setting up DeepSeek for completions..."
    deepseek_client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
    agent = Crig::Examples::DeepSeekNomicRag.build_agent(deepseek_client)
    puts "   ✓ DeepSeek agent ready"

    # Build chain
    puts "4. Building RAG chain..."
    chain = Crig::Examples::DeepSeekNomicRag.build_chain(store, agent)
    puts "   ✓ Chain built successfully"

    # Run examples
    puts "5. Running example queries:"
    puts "=" * 60
    
    Crig::Examples::DeepSeekNomicRag.example_prompts.each_with_index do |prompt, i|
      puts "\nExample #{i + 1}: #{prompt}"
      puts "-" * 40
      result = chain.call(prompt)
      puts "Response: #{result}"
      puts "-" * 40
      sleep(1.second)  # Rate limiting
    end

    puts "=" * 60
    puts ""
    puts "Summary: This hybrid RAG pipeline uses:"
    puts "1. Free local embeddings (Ollama nomic-embed-text)"
    puts "2. Low-cost cloud completions (DeepSeek, 10x cheaper than OpenAI)"
    puts "3. Multiple definitions per word for richer context"
    puts "4. Vector similarity search to find relevant definitions"
    puts ""
    puts "Total cost: ~$0.12 per 1M tokens (95% cheaper than OpenAI GPT-4)"
  else
    puts "DEEPSEEK_API_KEY not set."
    puts "This example uses a hybrid RAG pipeline:"
    puts "1. Ollama (free/local) for embeddings - already set up"
    puts "2. DeepSeek (cloud API) for completions - needs API key"
    puts ""
    puts "To run this example:"
    puts "  export DEEPSEEK_API_KEY=your_deepseek_key"
    puts "  crystal run examples/deepseek_nomic/rag.cr"
    puts ""
    puts "Note: You'll need to have Ollama running with nomic-embed-text model"
    puts "      already downloaded (you have this: ollama list shows nomic-embed-text)"
    puts ""
    puts "Cost comparison:"
    puts "  - OpenAI GPT-4 RAG: ~$2.63 per 1M tokens"
    puts "  - DeepSeek + Nomic RAG: ~$0.12 per 1M tokens"
    puts "  - Savings: 95% cost reduction"
  end
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