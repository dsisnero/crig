module Crig
  module Providers
    module Cohere
      struct EmbeddingResponse
        include JSON::Serializable

        @[JSON::Field(key: "response_type")]
        getter response_type : String?
        getter id : String
        getter embeddings : Array(Array(Float64))
        getter texts : Array(String)
        getter meta : Meta?

        def initialize(
          @id : String,
          @embeddings : Array(Array(Float64)),
          @texts : Array(String),
          @response_type : String? = nil,
          @meta : Meta? = nil,
        )
        end
      end

      struct Meta
        include JSON::Serializable

        @[JSON::Field(key: "api_version")]
        getter api_version : ApiVersion
        @[JSON::Field(key: "billed_units")]
        getter billed_units : BilledUnits
        getter warnings : Array(String)

        def initialize(@api_version : ApiVersion, @billed_units : BilledUnits, @warnings : Array(String) = [] of String)
        end
      end

      struct ApiVersion
        include JSON::Serializable

        getter version : String
        @[JSON::Field(key: "is_deprecated")]
        getter is_deprecated : Bool?
        @[JSON::Field(key: "is_experimental")]
        getter is_experimental : Bool?

        def initialize(@version : String, @is_deprecated : Bool? = nil, @is_experimental : Bool? = nil)
        end
      end

      struct BilledUnits
        include JSON::Serializable

        @[JSON::Field(key: "input_tokens")]
        getter input_tokens : Int32 = 0
        @[JSON::Field(key: "output_tokens")]
        getter output_tokens : Int32 = 0
        @[JSON::Field(key: "search_units")]
        getter search_units : Int32 = 0
        getter classifications : Int32 = 0

        def initialize(
          @input_tokens : Int32 = 0,
          @output_tokens : Int32 = 0,
          @search_units : Int32 = 0,
          @classifications : Int32 = 0,
        )
        end
      end

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        MAX_DOCUMENTS = 96

        getter client : Client
        getter model : String
        getter input_type : String
        getter ndims : Int32

        def initialize(@client : Client, @model : String, @input_type : String, @ndims : Int32)
        end

        def self.make(client : Client, model : String, ndims : Int32?) : self
          dims = ndims || Cohere.model_dimensions_from_identifier(model) || 0
          new(client, model, "search_document", dims)
        end

        def self.with_model(client : Client, model : String, input_type : String, ndims : Int32) : self
          new(client, model, input_type, ndims)
        end

        def max_documents : Int32
          MAX_DOCUMENTS
        end

        def embed_texts(texts : Enumerable(String)) : Array(Crig::Embeddings::Embedding)
          documents = texts.to_a

          body = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "texts" do
                json.array { documents.each { |document| json.string(document) } }
              end
              json.field "input_type", @input_type
            end
          end

          response = @client.post_json("/v1/embed", body.to_json)
          text = response.body
          raise Crig::Embeddings::EmbeddingError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          if error = parsed["message"]?.try(&.as_s?)
            raise Crig::Embeddings::EmbeddingError.new(error)
          end

          embedding_response = EmbeddingResponse.from_json(text)
          if embedding_response.embeddings.size != documents.size
            raise Crig::Embeddings::EmbeddingError.new("Expected #{documents.size} embeddings, got #{embedding_response.embeddings.size}")
          end

          embedding_response.embeddings.zip(documents).map do |embedding, document|
            Crig::Embeddings::Embedding.new(document, embedding)
          end
        end
      end
    end
  end
end
