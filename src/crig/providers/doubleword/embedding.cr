module Crig
  module Providers
    module Doubleword
      QWEN3_EMBEDDING_8B = "Qwen/Qwen3-Embedding-8B"

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        MAX_DOCUMENTS = 1024

        getter client : Client
        getter model : String
        getter ndims : Int32

        def initialize(@client : Client, @model : String, @ndims : Int32 = 0)
        end

        def self.make(client : Client, model : String, dims : Int32?) : self
          new(client, model, dims || 0)
        end

        def max_documents : Int32
          MAX_DOCUMENTS
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          documents = texts.to_a

          body = Crig::Providers::Internal::EmbeddingCompatible.build_request(
            @model,
            documents,
            @ndims,
            nil,
            nil,
            Crig::Providers::Internal::EmbeddingCompatible::Config.new(
              provider_name: "doubleword",
              supports_encoding_format: false,
              supports_user: false,
            ),
          )

          response = @client.post_json("/embeddings", body)
          text = response.body
          Crig::Providers::Internal::EmbeddingCompatible.check_response_status(response.status_code, text, Crig::Providers::Internal::EmbeddingCompatible::Config.new(provider_name: "doubleword", supports_encoding_format: false, supports_user: false))

          Crig::Providers::Internal::EmbeddingCompatible.parse_response(text, documents)
        end
      end
    end
  end
end
