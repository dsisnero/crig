module Crig
  module ToolEmbeddingDyn
    abstract def name : String
    abstract def context : JSON::Any
    abstract def embedding_docs : Array(String)
  end

  module Embeddings
    struct ToolSchema
      include JSON::Serializable

      getter name : String
      getter context : JSON::Any
      getter embedding_docs : Array(String)

      def initialize(@name : String, @context : JSON::Any, @embedding_docs : Array(String))
      end

      def self.try_from(tool : ::Crig::ToolEmbeddingDyn) : self
        new(tool.name, tool.context, tool.embedding_docs)
      end

      def embed(embedder : Crig::Embeddings::TextEmbedder) : Nil
        @embedding_docs.each { |doc| embedder.embed(doc) }
      end
    end
  end
end
