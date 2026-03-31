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

    annotation EmbedField
    end

    module Embed
      abstract def embed(embedder : TextEmbedder) : Nil
    end

    macro derive_embed(type)
      {% embed_methods = type.methods.select { |method| method.annotation(Crig::Embeddings::EmbedField) && method.args.empty? } %}

      {% if embed_methods.empty? %}
        {% raise "Add at least one zero-arg method tagged with @[Crig::Embeddings::EmbedField]." %}
      {% end %}

      include Crig::Embeddings::Embed

      def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
        {% for method in embed_methods %}
          {% if method.annotation(Crig::Embeddings::EmbedField)[:embed_with] %}
            {{ method.annotation(Crig::Embeddings::EmbedField)[:embed_with] }}(embedder, self.{{ method.name }})
          {% else %}
            Crig::Embeddings.append_embedded(embedder, self.{{ method.name }})
          {% end %}
        {% end %}
      end
    end

    def self.append_embedded(embedder : TextEmbedder, item : Embed) : Nil
      item.embed(embedder)
    end

    def self.append_embedded(embedder : TextEmbedder, item : String) : Nil
      embedder.embed(item)
    end

    def self.append_embedded(embedder : TextEmbedder, item : Number | Bool | Char) : Nil
      embedder.embed(item.to_s)
    end

    def self.append_embedded(embedder : TextEmbedder, item : JSON::Any) : Nil
      embedder.embed(item.to_json)
    end

    def self.append_embedded(embedder : TextEmbedder, item : Hash) : Nil
      embedder.embed(item.to_json)
    end

    def self.append_embedded(embedder : TextEmbedder, item : Tuple) : Nil
      item.each { |entry| append_embedded(embedder, entry) }
    end

    def self.append_embedded(embedder : TextEmbedder, item : Enumerable) : Nil
      item.each { |entry| append_embedded(embedder, entry) }
    end

    def self.append_embedded(embedder : TextEmbedder, item : ToolSchema) : Nil
      item.embedding_docs.each { |entry| embedder.embed(entry) }
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
  alias EmbedField = Embeddings::EmbedField
  alias ImageEmbeddingModel = Embeddings::ImageEmbeddingModel
  alias TextEmbedder = Embeddings::TextEmbedder
  alias ToolSchema = Embeddings::ToolSchema
  alias VectorDistance = Embeddings::VectorDistance
end
