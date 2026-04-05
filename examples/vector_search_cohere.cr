require "../src/crig"
require "./vector_search"

module Crig::Examples::VectorSearchCohere
  DOCUMENT_INPUT_TYPE = "search_document"
  QUERY_INPUT_TYPE    = "search_query"

  alias WordDefinition = Crig::Examples::VectorSearch::WordDefinition

  def self.build_store(
    client : Crig::Providers::Cohere::Client,
    model : String = Crig::Providers::Cohere::EMBED_ENGLISH_V3,
  ) : Tuple(Crig::Providers::Cohere::EmbeddingModel, Crig::Providers::Cohere::EmbeddingModel, Crig::InMemoryVectorStore(WordDefinition))
    document_model = client.embedding_model(model, DOCUMENT_INPUT_TYPE)
    search_model = client.embedding_model(model, QUERY_INPUT_TYPE)
    build_store(document_model, search_model)
  end

  def self.build_store(
    document_model : D,
    search_model : S,
  ) : Tuple(D, S, Crig::InMemoryVectorStore(WordDefinition)) forall D, S
    embeddings = Crig::Embeddings::EmbeddingsBuilder(typeof(document_model), WordDefinition).new(document_model)
      .documents(Crig::Examples::VectorSearch.word_definitions)
      .build
    store = Crig::InMemoryVectorStore(WordDefinition).from_documents_with_id_f(embeddings, &.id)
    {document_model, search_model, store}
  end

  def self.search(
    client : Crig::Providers::Cohere::Client,
    query : String = "Which instrument is found in the Nebulon Mountain Ranges?",
    samples : UInt64 = 1_u64,
    model : String = Crig::Providers::Cohere::EMBED_ENGLISH_V3,
  ) : Array(Tuple(Float64, String, String))
    _, search_model, store = build_store(client, model)
    request = Crig::VectorSearchRequest.builder
      .query(query)
      .samples(samples)
      .build

    store.index(search_model).top_n(request, WordDefinition).map do |score, id, document|
      {score, id, document.word}
    end
  end
end
