require "../src/crig"

module Crig::Examples::CustomVectorStore
  struct Document
    include JSON::Serializable

    getter title : String
    getter content : String

    def initialize(@title : String, @content : String)
    end
  end

  class MemoryVectorStore(E)
    getter key : String
    getter embedding_model : E

    @entries : Hash(String, Tuple(Crig::Embeddings::Embedding, JSON::Any))

    def initialize(@key : String, @embedding_model : E)
      @entries = {} of String => Tuple(Crig::Embeddings::Embedding, JSON::Any)
    end

    def self.new(
      key : String,
      embedding_model : E,
    ) : self forall E
      allocate.tap(&.initialize(key, embedding_model))
    end

    def add_document(id : String, content : String, metadata : T) : Nil forall T
      embedding = @embedding_model.embed_text(content)
      @entries[id] = {embedding, JSON.parse(metadata.to_json)}
    end

    def top_n(request : Crig::VectorSearchRequest, type : T.class) : Array(Tuple(Float64, String, T)) forall T
      scored_results(request).map do |score, id, metadata|
        {score, id, T.from_json(metadata.to_json)}
      end
    end

    def top_n_ids(request : Crig::VectorSearchRequest) : Array(Tuple(Float64, String))
      scored_results(request).map do |score, id, _metadata|
        {score, id}
      end
    end

    def top_n_results(request : Crig::VectorSearchRequest) : Crig::TopNResults
      scored_results(request).map do |score, id, metadata|
        {score, id, metadata}
      end
    end

    private def scored_results(request : Crig::VectorSearchRequest) : Array(Tuple(Float64, String, JSON::Any))
      query_embedding = @embedding_model.embed_text(request.query)

      @entries.map do |id, (embedding, metadata)|
        {embedding.cosine_similarity(query_embedding, false), id, metadata}
      end.sort_by { |score, _id, _metadata| -score }
        .first(request.samples.to_i)
    end
  end

  def self.sample_documents : Array(Document)
    [
      Document.new(
        "Rust Programming",
        "Rust is a systems programming language focused on safety and performance."
      ),
      Document.new(
        "Haskell Programming",
        "Haskell is a functional programming language known for its category theory informed abstractions"
      ),
      Document.new(
        "OCaml Programming",
        "OCaml is a functional programming language primarily concerned with pragmatism and systems programming."
      ),
      Document.new(
        "Machine Learning",
        "Machine learning is a subset of AI that enables systems to learn from data."
      ),
    ]
  end

  def self.build_store(embedding_model : E, key : String = "test_vectors") : MemoryVectorStore(E) forall E
    store = MemoryVectorStore(E).new(key, embedding_model)
    sample_documents.each_with_index do |document, index|
      store.add_document("doc_#{index}", document.content, document)
    end
    store
  end

  def self.request(
    query : String = "What programming language is best for systems programming?",
    samples : UInt64 = 2_u64,
  ) : Crig::VectorSearchRequest
    Crig::VectorSearchRequest.builder
      .query(query)
      .samples(samples)
      .build
  end

  def self.search(store, query : String = "What programming language is best for systems programming?", samples : UInt64 = 2_u64)
    store.top_n(request(query, samples), Document)
  end

  def self.search_ids(store, query : String = "What programming language is best for systems programming?", samples : UInt64 = 2_u64)
    store.top_n_ids(request(query, samples))
  end
end
