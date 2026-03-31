module Crig
  module Providers
    module OpenRouter
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
        getter usage : Usage?
        getter id : String?

        def initialize(
          @object : String,
          @data : Array(EmbeddingData),
          @model : String,
          @usage : Usage? = nil,
          @id : String? = nil,
        )
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
          new(client, model, ndims || 0)
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

          body = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "input" do
                json.array { documents.each { |document| json.string(document) } }
              end
              json.field "dimensions", @ndims if @ndims > 0
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
          raise Crig::Embeddings::EmbeddingError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          body_wrapper = ApiResponse(EmbeddingResponse).from_json_value(parsed) { |value| EmbeddingResponse.from_json(value.to_json) }
          if error = body_wrapper.error
            raise Crig::Embeddings::EmbeddingError.new(error.message)
          end

          embedding_response = body_wrapper.ok || raise Crig::Embeddings::EmbeddingError.new("OpenRouter embedding response did not include a success payload")
          if embedding_response.data.size != documents.size
            raise Crig::Embeddings::EmbeddingError.new("Response data length does not match input length")
          end

          embedding_response.data.zip(documents).map do |embedding, document|
            Crig::Embeddings::Embedding.new(document, embedding.embedding)
          end
        end
      end

      struct Client
        include Crig::EmbeddingsClient(Crig::Providers::OpenRouter::EmbeddingModel)
      end
    end
  end
end
