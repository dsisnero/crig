require "../../src/crig"

module Crig::Examples::DeepSeekChain
  def self.dictionary_texts : Array(String)
    [
      "Definition of a *flurbo*: A flurbo is a green alien that lives on cold planets",
      "Definition of a *glarb-glarb*: A glarb-glarb is a ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land.",
      "Definition of a *linglingdong*: A term used by inhabitants of the far side of the moon to describe humans.",
    ]
  end

  def self.build_store(model : M) : Crig::VectorStore::InMemoryVectorIndex(M, String) forall M
    embeddings = Crig::Embeddings.builder(model)
      .documents(dictionary_texts)
      .build

    store = Crig::VectorStore::InMemoryVectorStore(String).from_documents(embeddings)
    store.index(model)
  end

  def self.build_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
    client.agent(model)
      .preamble("You are a dictionary assistant here to assist the user in understanding the meaning of words.")
      .build
  end

  def self.build_chain(index, agent)
    Crig.pipeline
      .chain(
        Crig.parallel!(
          Crig.passthrough,
          Crig.pipeline.lookup(index, 1, String),
        )
      )
      .map do |(prompt, maybe_docs)|
        if error = maybe_docs.error
          "Error: #{error}! Prompting without additional context\n\n#{prompt}"
        else
          docs = maybe_docs.value || [] of Tuple(Float64, String, String)
          "Non standard word definitions:\n#{docs.map(&.[2]).join("\n")}\n\n#{prompt}"
        end
      end
      .prompt(agent)
  end

  def self.default_prompt : String
    "What does \"glarb-glarb\" mean?"
  end
# Main executable code - always run for examples
# Main executable code - only run when file is executed directly
if PROGRAM_NAME == __FILE__
  begin
  # Check if DEEPSEEK_API_KEY is set
  deepseek_api_key = ENV["DEEPSEEK_API_KEY"]?

  if deepseek_api_key
    puts "Setting up hybrid RAG pipeline:"
    puts "  - Embeddings: nomic-embed-text (Ollama, free/local)"
    puts "  - Completions: DeepSeek (cloud API)"
    puts ""

    # Create Ollama client for embeddings (free/local)
    puts "1. Setting up Ollama for embeddings..."
    ollama_client = Crig::Providers::Ollama::Client.new
    embedding_model = ollama_client.embedding_model("nomic-embed-text")
    puts "   ✓ Using nomic-embed-text (768 dimensions)"

    # Build vector store with Ollama embeddings
    puts "2. Creating vector store with embeddings..."
    store = Crig::Examples::DeepSeekChain.build_store(embedding_model)
    puts "   ✓ Vector store created with 3 documents"

    # Create DeepSeek client for completions
    puts "3. Setting up DeepSeek for completions..."
    deepseek_client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
    agent = Crig::Examples::DeepSeekChain.build_agent(deepseek_client)
    puts "   ✓ DeepSeek agent ready"

    # Build chain
    puts "4. Building RAG chain..."
    chain = Crig::Examples::DeepSeekChain.build_chain(store, agent)
    puts "   ✓ Chain built successfully"

    # Run chain
    puts "5. Running chain with prompt: \"#{Crig::Examples::DeepSeekChain.default_prompt}\""
    puts "=" * 60
    result = chain.call(Crig::Examples::DeepSeekChain.default_prompt)
    puts "\nDeepSeek + Nomic Chain result:"
    puts "=" * 60
    puts result
    puts "=" * 60
  else
    puts "DEEPSEEK_API_KEY not set."
    puts "This example uses:"
    puts "1. Ollama (free/local) for embeddings - requires nomic-embed-text model"
    puts "2. DeepSeek (cloud API) for completions - needs API key"
    puts ""
    puts "To run this example:"
    puts "  export DEEPSEEK_API_KEY=your_deepseek_key"
    puts "  crystal run examples/deepseek/chain.cr"
    puts ""
    puts "Note: You'll need to have Ollama running with nomic-embed-text model"
    puts "      Download it with: ollama pull nomic-embed-text"
    puts "      Start Ollama: ollama serve"
  end
rescue ex : IO::Error | Socket::Error
  STDERR.puts "Error: Could not connect to Ollama. Is Ollama running?"
  STDERR.puts "Start Ollama: ollama serve"
  exit 1
rescue ex
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
  exit 1
  end
