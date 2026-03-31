module Crig
  module Providers
    module Mistral
      MISTRAL_EMBED = "mistral-embed"
      MAX_DOCUMENTS = 1024

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

        getter id : String
        getter object : String
        getter model : String
        getter usage : Usage
        getter data : Array(EmbeddingData)

        def initialize(@id : String, @object : String, @model : String, @usage : Usage, @data : Array(EmbeddingData))
        end
      end

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        getter client : Client
        getter model : String
        getter ndims : Int32

        def initialize(@client : Client, @model : String, @ndims : Int32 = 0)
        end

        def self.make(client : Client, model : String, dims : Int32? = nil) : self
          new(client, model, dims || 0)
        end

        def self.with_model(client : Client, model : String, ndims : Int32 = 0) : self
          new(client, model, ndims)
        end

        def max_documents : Int32
          MAX_DOCUMENTS
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          documents = texts.to_a
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "input" do
                json.array { documents.each { |document| json.string(document) } }
              end
            end
          end

          response = @client.post_json("/v1/embeddings", payload.to_json)
          text = response.body
          raise Crig::Embeddings::EmbeddingError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          body = ApiResponse(EmbeddingResponse).from_json_value(parsed) { |value| EmbeddingResponse.from_json(value.to_json) }
          if error = body.error
            raise Crig::Embeddings::EmbeddingError.new(error.message)
          end
          response_body = body.ok || raise Crig::Embeddings::EmbeddingError.new("Mistral embedding response did not include a success payload")
          raise Crig::Embeddings::EmbeddingError.new("Response data length does not match input length") unless response_body.data.size == documents.size

          response_body.data.zip(documents).map do |embedding, document|
            Crig::Embeddings::Embedding.new(document, embedding.embedding)
          end
        end
      end
    end
  end
end
