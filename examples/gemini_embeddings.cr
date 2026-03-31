require "../src/crig"

module Crig::Examples::GeminiEmbeddings
  MODEL = Crig::Providers::Gemini::EMBEDDING_001

  struct Greetings
    include Crig::Embeddings::Embed

    getter message : String

    def initialize(@message : String)
    end

    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      embedder.embed(message)
    end
  end

  def self.build_embeddings(
    client : Crig::Providers::Gemini::Client,
    model : String = MODEL,
  ) : Crig::Embeddings::EmbeddingsBuilder(Crig::Providers::Gemini::EmbeddingModel, Greetings)
    client.embeddings(Greetings, model)
      .document(Greetings.new("Hello, world!"))
      .document(Greetings.new("Goodbye, world!"))
  end

  def self.build_embeddings(
    client : Crig::EmbeddingsClient(M),
    model : String = MODEL,
  ) : Crig::Embeddings::EmbeddingsBuilder(M, Greetings) forall M
    client.embeddings(Greetings, model)
      .document(Greetings.new("Hello, world!"))
      .document(Greetings.new("Goodbye, world!"))
  end
end
