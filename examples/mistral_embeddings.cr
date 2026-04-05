require "../src/crig"
require "./vector_search"

module Crig::Examples::MistralEmbeddings
  MODEL = Crig::Providers::Mistral::MISTRAL_EMBED

  alias WordDefinition = Crig::Examples::VectorSearch::WordDefinition

  def self.build_embeddings(
    client : Crig::Providers::Mistral::Client,
    model : String = MODEL,
  ) : Array(Tuple(WordDefinition, Crig::OneOrMany(Crig::Embeddings::Embedding)))
    embedding_model = client.embedding_model(model)
    build_embeddings(embedding_model)
  end

  def self.build_embeddings(
    embedding_model : M,
  ) : Array(Tuple(WordDefinition, Crig::OneOrMany(Crig::Embeddings::Embedding))) forall M
    Crig::Embeddings::EmbeddingsBuilder(typeof(embedding_model), WordDefinition).new(embedding_model)
      .documents(Crig::Examples::VectorSearch.word_definitions)
      .build
  end

  def self.search(
    client : Crig::Providers::Mistral::Client,
    query : String = "Hello world",
    samples : UInt64 = 1_u64,
    model : String = MODEL,
  ) : Array(Tuple(Float64, String, String))
    embedding_model = client.embedding_model(model)
    search(embedding_model, query, samples)
  end

  def self.search(
    embedding_model : M,
    query : String = "Hello world",
    samples : UInt64 = 1_u64,
  ) : Array(Tuple(Float64, String, String)) forall M
    store = Crig::InMemoryVectorStore(WordDefinition).from_documents(build_embeddings(embedding_model))
    request = Crig::VectorSearchRequest.builder
      .query(query)
      .samples(samples)
      .build

    store.index(embedding_model).top_n(request, WordDefinition).map do |score, id, document|
      {score, id, document.word}
    end
  end
end
