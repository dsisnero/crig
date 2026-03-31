require "../src/crig"

module Crig::Examples::VectorSearch
  struct WordDefinition
    include JSON::Serializable
    include Crig::Embeddings::Embed

    getter id : String
    getter word : String
    getter definitions : Array(String)

    def initialize(@id : String, @word : String, @definitions : Array(String))
    end

    def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
      @definitions.each do |definition|
        embedder.embed(definition)
      end
    end
  end

  def self.word_definitions : Array(WordDefinition)
    [
      WordDefinition.new(
        "doc0",
        "flurbo",
        [
          "A green alien that lives on cold planets.",
          "A fictional digital currency that originated in the animated series Rick and Morty.",
        ]
      ),
      WordDefinition.new(
        "doc1",
        "glarb-glarb",
        [
          "An ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land.",
          "A fictional creature found in the distant, swampy marshlands of the planet Glibbo in the Andromeda galaxy.",
        ]
      ),
      WordDefinition.new(
        "doc2",
        "linglingdong",
        [
          "A term used by inhabitants of the sombrero galaxy to describe humans.",
          "A rare, mystical instrument crafted by the ancient monks of the Nebulon Mountain Ranges on the planet Quarm.",
        ]
      ),
    ]
  end

  def self.build_store(model) : Crig::InMemoryVectorStore(WordDefinition)
    embeddings = Crig::Embeddings::EmbeddingsBuilder(typeof(model), WordDefinition).new(model)
      .documents(word_definitions)
      .build

    Crig::InMemoryVectorStore(WordDefinition).from_documents_with_id_f(embeddings) do |document|
      document.id
    end
  end

  def self.build_index(
    client : Crig::Providers::OpenAI::Client,
    embedding_model : String = Crig::Providers::OpenAI::TEXT_EMBEDDING_ADA_002,
  ) : Crig::InMemoryVectorIndex(Crig::Providers::OpenAI::EmbeddingModel, WordDefinition)
    model = client.embedding_model(embedding_model)
    build_store(model).index(model)
  end

  def self.request(query : String = default_query, samples : UInt64 = 1_u64) : Crig::VectorSearchRequest
    Crig::VectorSearchRequest.builder
      .query(query)
      .samples(samples)
      .build
  end

  def self.search(index, query : String = default_query, samples : UInt64 = 1_u64) : Array(Tuple(Float64, String, String))
    index.top_n(request(query, samples), WordDefinition).map do |score, id, document|
      {score, id, document.word}
    end
  end

  def self.search_ids(index, query : String = default_query, samples : UInt64 = 1_u64) : Array(Tuple(Float64, String))
    index.top_n_ids(request(query, samples))
  end

  def self.default_query : String
    "I need to buy something in a fictional universe. What type of money can I use for this?"
  end
end
