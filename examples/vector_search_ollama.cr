require "../src/crig"
require "./vector_search"

module Crig::Examples::VectorSearchOllama
  BASE_URL = "http://localhost:11434"
  MODEL    = "nomic-embed-text"

  alias WordDefinition = Crig::Examples::VectorSearch::WordDefinition

  def self.build_client(base_url : String = BASE_URL) : Crig::Providers::Ollama::Client
    Crig::Providers::Ollama::Client.builder
      .api_key(Crig::Nothing.new)
      .base_url(base_url)
      .build
  end

  def self.build_store(
    client : Crig::Providers::Ollama::Client,
    model : String = MODEL,
  ) : Tuple(Crig::Providers::Ollama::EmbeddingModel, Crig::InMemoryVectorStore(WordDefinition))
    embedding_model = client.embedding_model(model)
    build_store(embedding_model)
  end

  def self.build_store(
    embedding_model : M,
  ) : Tuple(M, Crig::InMemoryVectorStore(WordDefinition)) forall M
    embeddings = Crig::Embeddings::EmbeddingsBuilder(typeof(embedding_model), WordDefinition).new(embedding_model)
      .documents(Crig::Examples::VectorSearch.word_definitions)
      .build
    store = Crig::InMemoryVectorStore(WordDefinition).from_documents_with_id_f(embeddings, &.id)
    {embedding_model, store}
  end

  def self.search(
    client : Crig::Providers::Ollama::Client,
    query : String = Crig::Examples::VectorSearch.default_query,
    samples : UInt64 = 1_u64,
    model : String = MODEL,
  ) : Tuple(Array(Tuple(Float64, String, String)), Array(Tuple(Float64, String)))
    embedding_model, store = build_store(client, model)
    request = Crig::VectorSearchRequest.builder
      .query(query)
      .samples(samples)
      .build
    index = store.index(embedding_model)

    results = index.top_n(request, WordDefinition).map do |score, id, document|
      {score, id, document.word}
    end
    id_results = index.top_n_ids(request)
    {results, id_results}
  end
end
