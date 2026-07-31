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
          embed_texts_with_usage(texts).embeddings
        end

        def embed_texts_with_usage(texts : Enumerable(String)) : Crig::Embeddings::EmbeddingResponse
          config = Crig::Providers::Internal::EmbeddingCompatible::Config.new(
            provider_name: "openrouter",
            requires_usage: false,
            supports_encoding_format: true,
            supports_user: true,
          )

          Crig::Providers::Internal::EmbeddingCompatible.validate_parameters(@encoding_format.try(&.to_wire), @user, config)

          documents = texts.to_a

          body = Crig::Providers::Internal::EmbeddingCompatible.build_request(
            @model,
            documents,
            @ndims,
            @encoding_format.try(&.to_wire),
            @user,
            config,
          )

          response = @client.post_json("/embeddings", body)
          text = response.body
          Crig::Providers::Internal::EmbeddingCompatible.check_response_status(response.status_code, text, config)

          parsed = JSON.parse(text)
          if error = parsed["error"]?
            raise Crig::Embeddings::EmbeddingError.new(error["message"].as_s)
          end

          Crig::Providers::Internal::EmbeddingCompatible.parse_response_with_usage(text, documents, config)
        end
      end

      struct Client
        include Crig::EmbeddingsClient(Crig::Providers::OpenRouter::EmbeddingModel)
      end
    end
  end
end
