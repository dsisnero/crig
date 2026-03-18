module Crig
  module Embeddings
    class EmbeddingError < Exception
    end

    struct Embedding
      include JSON::Serializable

      getter document : String
      getter vec : Array(Float64)

      def initialize(@document : String = "", @vec : Array(Float64) = [] of Float64)
      end

      def ==(other : self) : Bool
        @document == other.document
      end
    end

    module EmbeddingModel
      abstract def max_documents : Int32
      abstract def ndims : Int32
      abstract def embed_texts(texts : Enumerable(String)) : Array(Embedding)

      def embed_text(text : String) : Embedding
        embed_texts([text]).first? || raise EmbeddingError.new("There should be at least one embedding")
      end
    end

    module EmbeddingModelDyn
      abstract def max_documents : Int32
      abstract def ndims : Int32
      abstract def embed_text(text : String) : Embedding
      abstract def embed_texts(texts : Array(String)) : Array(Embedding)
    end

    module ImageEmbeddingModel
      abstract def max_documents : Int32
      abstract def ndims : Int32
      abstract def embed_images(images : Enumerable(Bytes)) : Array(Embedding)

      def embed_image(bytes : Bytes) : Embedding
        embed_images([bytes]).first? || raise EmbeddingError.new("There should be at least one embedding")
      end
    end
  end
end
