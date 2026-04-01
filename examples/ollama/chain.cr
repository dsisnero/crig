require "../../src/crig"

module Crig::Examples::OllamaChain
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
    client : Crig::Providers::Ollama::Client,
    model : String = Crig::Providers::Ollama::LLAMA3_2,
  ) : Crig::Agent(Crig::Providers::Ollama::CompletionModel)
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
end

# Main executable code - always run for examples
begin
  puts "Setting up completely free RAG pipeline using Ollama:"
  puts "  - Embeddings: nomic-embed-text (free/local)"
  puts "  - Completions: llama3.2 (free/local)"
  puts ""

  # Create Ollama client (no API key needed for local Ollama)
  # Default base_url is "http://localhost:11434"
  puts "1. Setting up Ollama client..."
  ollama_client = Crig::Providers::Ollama::Client.new
  puts "   ✓ Connected to Ollama at http://localhost:11434"

  # Build agent using Ollama completion model
  puts "2. Creating agent with llama3.2..."
  agent = Crig::Examples::OllamaChain.build_agent(ollama_client)
  puts "   ✓ Agent ready with llama3.2"

  # Build embeddings model and store using Ollama embedding model
  # Using nomic-embed-text (768 dimensions) - a good free embedding model
  puts "3. Setting up embeddings with nomic-embed-text..."
  embedding_model = ollama_client.embedding_model(Crig::Providers::Ollama::NOMIC_EMBED_TEXT)
  store = Crig::Examples::OllamaChain.build_store(embedding_model)
  puts "   ✓ Vector store created with 3 documents (768 dimensions)"

  # Build chain
  puts "4. Building RAG chain..."
  chain = Crig::Examples::OllamaChain.build_chain(store, agent)
  puts "   ✓ Chain built successfully"

  # Run chain
  puts "5. Running chain with prompt: \"#{Crig::Examples::OllamaChain.default_prompt}\""
  puts "=" * 60
  result = chain.call(Crig::Examples::OllamaChain.default_prompt)
  puts "\nOllama Chain result:"
  puts "=" * 60
  puts result
  puts "=" * 60
rescue ex : IO::Error | Socket::Error
  STDERR.puts "Error: Could not connect to Ollama. Is Ollama running?"
  STDERR.puts "To run this example locally for free:"
  STDERR.puts "1. Install Ollama from https://ollama.com"
  STDERR.puts "2. Start Ollama: ollama serve"
  STDERR.puts "3. Pull the required models:"
  STDERR.puts "   ollama pull nomic-embed-text  # for embeddings"
  STDERR.puts "   ollama pull llama3.2          # for completions"
  STDERR.puts "4. Run this example again"
  exit 1
rescue ex
  STDERR.puts "Error: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
  exit 1
end
