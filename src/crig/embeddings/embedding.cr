module Crig
  module Embeddings
    class EmbeddingError < Exception
      enum Kind
        HttpError
        JsonError
        UrlError
        DocumentError
        ResponseError
        ProviderError
        Other
      end

      getter kind : Kind
      getter source_error : Exception?
      getter detail : String?

      def initialize(
        @kind : Kind = Kind::Other,
        message : String? = nil,
        @source_error : Exception? = nil,
        @detail : String? = nil,
      )
        super(message || build_message)
      end

      def initialize(message : String)
        @kind = Kind::Other
        @source_error = nil
        @detail = message
        super(message)
      end

      def self.http_error(error : Exception) : self
        new(Kind::HttpError, source_error: error)
      end

      def self.json_error(error : Exception) : self
        new(Kind::JsonError, source_error: error)
      end

      def self.url_error(error : Exception) : self
        new(Kind::UrlError, source_error: error)
      end

      def self.document_error(error : Exception) : self
        new(Kind::DocumentError, source_error: error)
      end

      def self.response_error(detail : String) : self
        new(Kind::ResponseError, detail: detail)
      end

      def self.provider_error(detail : String) : self
        new(Kind::ProviderError, detail: detail)
      end

      private def build_message : String
        case @kind
        when Kind::HttpError
          "HttpError: #{source_message}"
        when Kind::JsonError
          "JsonError: #{source_message}"
        when Kind::UrlError
          "UrlError: #{source_message}"
        when Kind::DocumentError
          "DocumentError: #{source_message}"
        when Kind::ResponseError
          "ResponseError: #{@detail}"
        when Kind::ProviderError
          "ProviderError: #{@detail}"
        else
          @detail || source_message
        end
      end

      private def source_message : String
        @source_error.try(&.message) || @source_error.to_s
      end
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
