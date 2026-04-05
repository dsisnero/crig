require "../src/crig"

module Crig::Examples::VoyageAIEmbeddings
  MODEL = Crig::Providers::VoyageAI::VOYAGE_3_LARGE

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
    client : Crig::Providers::VoyageAI::Client,
    model : String = MODEL,
  ) : Crig::Embeddings::EmbeddingsBuilder(Crig::Providers::VoyageAI::EmbeddingModel, Greetings)
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
