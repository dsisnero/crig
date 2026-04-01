require "../../src/crig"

module Crig::Examples::DeepSeekNomicPdfAgent
  # Document structure for embedding
  struct Document
    include JSON::Serializable
    include Crig::Embeddings::Embed
    
    getter id : String
    getter content : String
    
    def initialize(@id : String, @content : String)
    end
    
    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      embedder.embed(@content)
    end
  end
  
  # Load PDF and chunk it
  def self.load_and_chunk_pdf(pdf_path : String, chunk_size : Int32 = 2000) : Array(String)
    chunks = [] of String
    
    # Load PDF using Rig's PDF loader
    loader = Crig::Loaders::PdfFileLoader.with_glob(pdf_path)
    
    loader.read.each do |result|
      case result
      when String
        # Split content into chunks
        current_chunk = ""
        result.split(/\s+/).each do |word|
          if current_chunk.size + word.size + 1 > chunk_size && !current_chunk.empty?
            chunks << current_chunk.strip
            current_chunk = ""
          end
          current_chunk += word + " "
        end
        
        # Add the last chunk if not empty
        if !current_chunk.empty?
          chunks << current_chunk.strip
        end
      when Crig::Loaders::PdfLoaderError
        STDERR.puts "Error loading PDF: #{result.message}"
      end
    end
    
    if chunks.empty?
      raise "No content found in PDF file: #{pdf_path}"
    end
    
    chunks
  end
  
  # Build vector store from PDF chunks
  def self.build_pdf_store(
    pdf_chunks : Array(String),
    embedding_model : M
  ) : Crig::VectorStore::InMemoryVectorIndex(M, Document) forall M
    # Create Document objects from chunks
    documents = pdf_chunks.map_with_index do |chunk, i|
      Document.new(id: "pdf_chunk_#{i}", content: chunk)
    end
    
    # Handle empty case (shouldn't happen due to earlier check, but helps compiler)
    if documents.empty?
      raise "No documents to embed"
    end
    
    # Use .documents() method - most ergonomic API
    # The compiler now knows documents is not empty
    builder = Crig::Embeddings.builder(embedding_model).documents(documents)
    
    # builder is definitely EmbeddingsBuilder now, not EmbeddingsBuilderInitializer
    embeddings_result = builder.build
    
    # Create vector store and index
    store = Crig::VectorStore::InMemoryVectorStore(Document).from_documents(embeddings_result)
    store.index(embedding_model)
  end
  
  # Build RAG agent with dynamic context
  def self.build_rag_agent(
    client : Crig::Providers::DeepSeek::Client,
    index : Crig::VectorStore::VectorStoreIndex(M, Document),
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel) forall M
    client.agent(model)
      .preamble(<<-TEXT
        You are a helpful assistant that answers questions based on the provided document context.
        When answering questions, try to synthesize information from multiple chunks if they're related.
        If the context doesn't contain relevant information, say so rather than making up an answer.
      TEXT
      )
      .dynamic_context(3, index)  # Use top 3 relevant chunks
      .temperature(0.3)  # Lower temperature for factual responses
      .build
  end
  
  # Simple interactive chat loop
  def self.interactive_chat(agent : Crig::Agent(M)) forall M
    puts "\n📚 PDF Chat Assistant (type 'quit' or 'exit' to end)"
    puts "=" * 60
    
    loop do
      print "\nYou: "
      user_input = gets.try(&.chomp)
      
      break if user_input.nil?
      
      case user_input.downcase
      when "quit", "exit", "q"
        puts "Goodbye!"
        break
      when ""
        next
      else
        print "Assistant: "
        STDOUT.flush
        
        begin
          response = agent.prompt(user_input).send
          puts response
        rescue ex : Crig::Completion::CompletionError
          puts "Error: #{ex.message}"
        rescue ex
          puts "Unexpected error: #{ex.message}"
        end
      end
    end
  end
end

# Main executable code - always run for examples
begin
  # Check if DEEPSEEK_API_KEY is set
  deepseek_api_key = ENV["DEEPSEEK_API_KEY"]?
  
  if deepseek_api_key
    puts "Setting up PDF RAG agent with DeepSeek + Nomic:"
    puts "  - Embeddings: nomic-embed-text (Ollama, free/local)"
    puts "  - Completions: DeepSeek Chat (cloud API, ~10x cheaper than OpenAI)"
    puts "  - PDF: DeepSeek R1 research paper"
    puts "  - Cost: ~$0.12 per 1M tokens (vs $2.63 for OpenAI)"
    puts ""
    
    # Create Ollama client for embeddings (free/local)
    puts "1. Setting up Ollama for embeddings..."
    ollama_client = Crig::Providers::Ollama::Client.new
    embedding_model = ollama_client.embedding_model("nomic-embed-text")
    puts "   ✓ Using nomic-embed-text (768 dimensions)"
    
    # Load and chunk PDF
    puts "2. Loading and chunking PDF document..."
    pdf_path = "vendor/rig/rig/rig-core/examples/documents/deepseek_r1.pdf"
    
    unless File.exists?(pdf_path)
      puts "   ⚠️  PDF not found at: #{pdf_path}"
      puts "   Downloading sample PDF..."
      
      # Try to create documents directory
      documents_dir = "examples/documents"
      Dir.mkdir_p(documents_dir)
      
      # Provide instructions for getting the PDF
      puts "   Please download the DeepSeek R1 paper:"
      puts "   https://github.com/0xPlaygrounds/rig/raw/main/rig-core/examples/documents/deepseek_r1.pdf"
      puts "   And save it to: #{documents_dir}/deepseek_r1.pdf"
      puts ""
      puts "   Then run this example again."
      exit 1
    end
    
    pdf_chunks = Crig::Examples::DeepSeekNomicPdfAgent.load_and_chunk_pdf(pdf_path)
    puts "   ✓ Loaded #{pdf_chunks.size} chunks from PDF"
    
    # Build vector index
    puts "3. Creating vector index from PDF chunks..."
    index = Crig::Examples::DeepSeekNomicPdfAgent.build_pdf_store(pdf_chunks, embedding_model)
    puts "   ✓ Vector index created with #{pdf_chunks.size} document chunks"
    
    # Create DeepSeek client for completions
    puts "4. Setting up DeepSeek for completions..."
    deepseek_client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
    agent = Crig::Examples::DeepSeekNomicPdfAgent.build_rag_agent(deepseek_client, index)
    puts "   ✓ DeepSeek RAG agent ready"
    
    # Show example questions
    puts ""
    puts "5. Example questions you can ask:"
    puts "   • What is DeepSeek R1?"
    puts "   • What are the key innovations in this paper?"
    puts "   • How does DeepSeek R1 compare to other models?"
    puts "   • What evaluation methods were used?"
    puts "   • What are the main findings?"
    puts ""
    
    # Start interactive chat
    Crig::Examples::DeepSeekNomicPdfAgent.interactive_chat(agent)
    
    puts ""
    puts "Summary: This PDF RAG pipeline uses:"
    puts "1. Free local embeddings (Ollama nomic-embed-text)"
    puts "2. Low-cost cloud completions (DeepSeek, 10x cheaper than OpenAI)"
    puts "3. PDF document parsing and chunking"
    puts "4. Vector similarity search for relevant context"
    puts "5. Dynamic context injection into prompts"
    puts ""
    puts "Total cost: ~$0.12 per 1M tokens (95% cheaper than OpenAI GPT-4)"
  else
    puts "DEEPSEEK_API_KEY not set."
    puts "This example uses a hybrid PDF RAG pipeline:"
    puts "1. Ollama (free/local) for embeddings - already set up"
    puts "2. DeepSeek (cloud API) for completions - needs API key"
    puts "3. PDF document: DeepSeek R1 research paper"
    puts ""
    puts "To run this example:"
    puts "  1. Download the PDF:"
    puts "     mkdir -p examples/documents"
    puts "     curl -L https://github.com/0xPlaygrounds/rig/raw/main/rig-core/examples/documents/deepseek_r1.pdf \\"
    puts "          -o examples/documents/deepseek_r1.pdf"
    puts ""
    puts "  2. Set API key:"
    puts "     export DEEPSEEK_API_KEY=your_deepseek_key"
    puts ""
    puts "  3. Run the example:"
    puts "     crystal run examples/deepseek_nomic/pdf_agent.cr"
    puts ""
    puts "Note: DeepSeek API is significantly cheaper than OpenAI (~10x cheaper)."
    puts "      Get a free API key at: https://platform.deepseek.com/"
    puts ""
    puts "Cost comparison:"
    puts "  - OpenAI GPT-4 PDF RAG: ~$2.63 per 1M tokens"
    puts "  - DeepSeek + Nomic PDF RAG: ~$0.12 per 1M tokens"
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