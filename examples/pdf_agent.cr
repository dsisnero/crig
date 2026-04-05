require "../src/crig"

module Crig::Examples::PdfAgent
  BASE_URL         = "http://localhost:11434/v1"
  EMBEDDING_MODEL  = "bge-m3"
  COMPLETION_MODEL = "deepseek-r1"
  PREAMBLE         = "You are a helpful assistant that answers questions based on the provided document context. When answering questions, try to synthesize information from multiple chunks if they're related."
  PDF_PATH         = "vendor/rig/rig/rig-core/examples/documents/deepseek_r1.pdf"
  CHUNK_SIZE       = 2000

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

  def self.build_client(base_url : String = BASE_URL) : Crig::Providers::Ollama::Client
    Crig::Providers::Ollama::Client.builder
      .api_key(Crig::Nothing.new)
      .base_url(base_url)
      .build
  end

  def self.load_pdf(path : String = PDF_PATH, chunk_size : Int32 = CHUNK_SIZE) : Array(String)
    chunks = [] of String

    Crig::Loaders::PdfFileLoader.with_glob(path).read.each do |result|
      case result
      when String
        current = ""
        result.split(/\s+/).each do |word|
          if current.size + word.size + 1 > chunk_size && !current.empty?
            chunk = current.strip
            chunks << chunk unless chunk.empty?
            current = ""
          end
          current += word
          current += ' '
        end
        chunk = current.strip
        chunks << chunk unless chunk.empty?
      when Crig::Loaders::PdfLoaderError
        STDERR.puts "Error reading PDF content: #{result.message}"
      end
    end

    raise "No content found in PDF file: #{path}" if chunks.empty?
    chunks
  end

  def self.build_embeddings(
    embedding_model : M,
    pdf_chunks : Enumerable(String),
  ) forall M
    builder = Crig::Embeddings::EmbeddingsBuilder(M, Document).empty(embedding_model)
    pdf_chunks.each_with_index do |chunk, index|
      builder = builder.document(Document.new("pdf_document_#{index}", chunk))
    end
    builder.build
  end

  def self.build_index(
    embedding_model : M,
    pdf_chunks : Enumerable(String),
  ) forall M
    embeddings = build_embeddings(embedding_model, pdf_chunks)
    store = Crig::InMemoryVectorStore(Document).from_documents(embeddings)
    store.index(embedding_model)
  end

  def self.build_agent(
    client : Crig::Providers::Ollama::Client,
    index,
    model : String = COMPLETION_MODEL,
  ) : Crig::Agent(Crig::Providers::Ollama::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .dynamic_context(1, index)
      .build
  end

  def self.build_chatbot(
    agent : Crig::Agent(M),
    max_turns : Int32 = 10,
  ) forall M
    Crig::Integrations::ChatBotBuilder(Crig::Integrations::NoImplProvided).new
      .agent(agent)
      .max_turns(max_turns)
      .build
  end
end
