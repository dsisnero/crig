module Crig
  module Providers
    module OpenAI
      TEXT_EMBEDDING_3_LARGE = "text-embedding-3-large"
      TEXT_EMBEDDING_3_SMALL = "text-embedding-3-small"
      TEXT_EMBEDDING_ADA_002 = "text-embedding-ada-002"

      enum EncodingFormat
        Float
        Base64

        def to_wire : String
          to_s.downcase
        end
      end

      struct EmbeddingData
        include JSON::Serializable

        getter object : String
        getter embedding : Array(Float64)
        getter index : Int32

        def initialize(@object : String, @embedding : Array(Float64), @index : Int32)
        end
      end

      struct EmbeddingResponse
        include JSON::Serializable

        getter object : String
        getter data : Array(EmbeddingData)
        getter model : String
        getter usage : OpenAIUsage

        def initialize(@object : String, @data : Array(EmbeddingData), @model : String, @usage : OpenAIUsage)
        end
      end

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        MAX_DOCUMENTS = 1024

        getter client : Client
        getter model : String
        getter encoding_format : EncodingFormat?
        getter user : String?
        getter ndims : Int32

        def initialize(
          @client : Client,
          @model : String,
          @ndims : Int32,
          @encoding_format : EncodingFormat? = nil,
          @user : String? = nil,
        )
        end

        def self.make(client : Client, model : String, ndims : Int32?) : self
          dims = ndims || model_dimensions_from_identifier(model) || 0
          new(client, model, dims)
        end

        def self.with_model(client : Client, model : String, ndims : Int32) : self
          new(client, model, ndims)
        end

        def self.with_encoding_format(client : Client, model : String, ndims : Int32, encoding_format : EncodingFormat) : self
          new(client, model, ndims, encoding_format)
        end

        def max_documents : Int32
          MAX_DOCUMENTS
        end

        def encoding_format(encoding_format : EncodingFormat) : self
          self.class.new(@client, @model, @ndims, encoding_format, @user)
        end

        def user(user : String) : self
          self.class.new(@client, @model, @ndims, @encoding_format, user)
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          documents = texts.to_a

          body = OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "input" do
                json.array do
                  documents.each { |document| json.string(document) }
                end
              end
              if @ndims > 0 && @model != TEXT_EMBEDDING_ADA_002
                json.field "dimensions", @ndims
              end
              if encoding_format = @encoding_format
                json.field "encoding_format", encoding_format.to_wire
              end
              if user = @user
                json.field "user", user
              end
            end
          end

          response = @client.post_json("/embeddings", body.to_json)
          text = response.body

          if response.status_code >= 400
            raise Crig::Embeddings::EmbeddingError.new(text)
          end

          parsed = JSON.parse(text)
          if error = parsed["error"]?
            raise Crig::Embeddings::EmbeddingError.new(error["message"].as_s)
          end

          embedding_response = EmbeddingResponse.from_json(text)
          if embedding_response.data.size != documents.size
            raise Crig::Embeddings::EmbeddingError.new("Response data length does not match input length")
          end

          embedding_response.data.zip(documents).map do |embedding, document|
            Crig::Embeddings::Embedding.new(document, embedding.embedding)
          end
        end

        private def self.model_dimensions_from_identifier(identifier : String) : Int32?
          case identifier
          when TEXT_EMBEDDING_3_LARGE
            3072
          when TEXT_EMBEDDING_3_SMALL, TEXT_EMBEDDING_ADA_002
            1536
          end
        end
      end

      struct Client
        include Crig::EmbeddingsClient(Crig::Providers::OpenAI::EmbeddingModel)
      end
    end
  end
end
