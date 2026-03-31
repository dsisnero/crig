module Crig
  module Providers
    module Together
      BGE_BASE_EN_V1_5                = "BAAI/bge-base-en-v1.5"
      BGE_LARGE_EN_V1_5               = "BAAI/bge-large-en-v1.5"
      BERT_BASE_UNCASED               = "bert-base-uncased"
      M2_BERT_2K_RETRIEVAL_ENCODER_V1 = "hazyresearch/M2-BERT-2k-Retrieval-Encoder-V1"
      M2_BERT_80M_32K_RETRIEVAL       = "togethercomputer/m2-bert-80M-32k-retrieval"
      M2_BERT_80M_2K_RETRIEVAL        = "togethercomputer/m2-bert-80M-2k-retrieval"
      M2_BERT_80M_8K_RETRIEVAL        = "togethercomputer/m2-bert-80M-8k-retrieval"
      SENTENCE_BERT                   = "sentence-transformers/msmarco-bert-base-dot-v5"
      UAE_LARGE_V1                    = "WhereIsAI/UAE-Large-V1"

      struct EmbeddingData
        include JSON::Serializable

        getter object : String
        getter embedding : Array(Float64)
        getter index : Int32

        def initialize(@object : String, @embedding : Array(Float64), @index : Int32)
        end
      end

      struct Usage
        include JSON::Serializable

        getter prompt_tokens : Int32
        getter total_tokens : Int32

        def initialize(@prompt_tokens : Int32, @total_tokens : Int32)
        end
      end

      struct EmbeddingResponse
        include JSON::Serializable

        getter model : String
        getter object : String
        getter data : Array(EmbeddingData)

        def initialize(@model : String, @object : String, @data : Array(EmbeddingData))
        end
      end

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        MAX_DOCUMENTS = 1024

        getter client : Client
        getter model : String
        getter ndims : Int32

        def initialize(@client : Client, @model : String, @ndims : Int32 = 0)
        end

        def self.make(client : Client, model : String, dims : Int32? = nil) : self
          new(client, model, dims || 0)
        end

        def max_documents : Int32
          MAX_DOCUMENTS
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          docs = texts.to_a
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "input" do
                json.array do
                  docs.each { |document| json.string(document) }
                end
              end
            end
          end

          response = @client.post_json("/v1/embeddings", payload.to_json)
          body = response.body
          raise Crig::Embeddings::EmbeddingError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          envelope = ApiResponse(EmbeddingResponse).from_json_value(parsed) { |value| EmbeddingResponse.from_json(value.to_json) }
          if error = envelope.error
            raise Crig::Embeddings::EmbeddingError.new(error.message)
          end
          result = envelope.ok || raise Crig::Embeddings::EmbeddingError.new("Together response did not include a success payload")
          raise Crig::Embeddings::EmbeddingError.new("Response data length does not match input length") unless result.data.size == docs.size

          result.data.zip(docs).map do |embedding, document|
            Crig::Embeddings::Embedding.new(document, embedding.embedding)
          end
        end
      end

      struct Client
        include Crig::EmbeddingsClient(Crig::Providers::Together::EmbeddingModel)
      end
    end
  end
end
