require "./embeddings/embedding"
require "./embeddings/builder"
require "./embeddings/distance"
require "./embeddings/tool"

module Crig
  module Embeddings
    class EmbedError < Exception
      def self.new(error : Exception) : self
        allocate.tap do |value|
          value.initialize(error.message || error.class.name)
        end
      end
    end

    class TextEmbedder
      getter texts : Array(String)

      def initialize
        @texts = [] of String
      end

      def embed(text : String) : Nil
        @texts << text
      end
    end

    module Embed
      abstract def embed(embedder : TextEmbedder) : Nil
    end

    def self.to_texts(item : Embed) : Array(String)
      embedder = TextEmbedder.new
      item.embed(embedder)
      embedder.texts.dup
    end

    def self.to_texts(item : String) : Array(String)
      [item]
    end

    def self.to_texts(item : Number | Bool | Char) : Array(String)
      [item.to_s]
    end

    def self.to_texts(item : JSON::Any) : Array(String)
      [item.to_json]
    end

    def self.to_texts(items : Array(String)) : Array(String)
      items.dup
    end

    def self.to_texts(items : Hash) : Array(String)
      [items.to_json]
    end

    def self.to_texts(items : Tuple) : Array(String)
      items.to_a.flat_map { |item| to_texts(item) }
    end

    def self.to_texts(items : Enumerable) : Array(String)
      items.flat_map { |item| to_texts(item) }
    end

    def self.to_texts(item : ToolSchema) : Array(String)
      item.embedding_docs.dup
    end
  end

  alias Embed = Embeddings::Embed
  alias EmbedError = Embeddings::EmbedError
  alias Embedding = Embeddings::Embedding
  alias EmbeddingError = Embeddings::EmbeddingError
  alias EmbeddingsBuilder = Embeddings::EmbeddingsBuilder
  alias EmbeddingModel = Embeddings::EmbeddingModel
  alias EmbeddingModelDyn = Embeddings::EmbeddingModelDyn
  alias ImageEmbeddingModel = Embeddings::ImageEmbeddingModel
  alias TextEmbedder = Embeddings::TextEmbedder
  alias ToolSchema = Embeddings::ToolSchema
  alias VectorDistance = Embeddings::VectorDistance
end
