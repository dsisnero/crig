require "http/client"

module Crig
  module Providers
    module VoyageAI
      VOYAGEAI_API_BASE_URL = "https://api.voyageai.com/v1"

      VOYAGE_3_LARGE   = "voyage-3-large"
      VOYAGE_3_5       = "voyage-3.5"
      VOYAGE_3_5_LITE  = "voyage.3-5.lite"
      VOYAGE_CODE_3    = "voyage-code-3"
      VOYAGE_FINANCE_2 = "voyage-finance-2"
      VOYAGE_LAW_2     = "voyage-law-2"
      VOYAGE_CODE_2    = "voyage-code-2"

      struct VoyageExt
      end

      struct VoyageBuilder
      end

      def self.model_dimensions_from_identifier(model_identifier : String) : Int32?
        case model_identifier
        when VOYAGE_CODE_2
          1536
        when VOYAGE_3_LARGE, VOYAGE_3_5, VOYAGE_3_5_LITE, VOYAGE_CODE_3, VOYAGE_FINANCE_2, VOYAGE_LAW_2
          1024
        end
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = VOYAGEAI_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          key = @api_key || raise "VOYAGE_API_KEY not set"
          Client.new(key, @base_url)
        end
      end

      struct Usage
        include JSON::Serializable

        getter prompt_tokens : Int32
        getter total_tokens : Int32

        def initialize(@prompt_tokens : Int32, @total_tokens : Int32)
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
        getter usage : Usage

        def initialize(@object : String, @data : Array(EmbeddingData), @model : String, @usage : Usage)
        end
      end

      struct ApiErrorResponse
        include JSON::Serializable

        getter message : String

        def initialize(@message : String)
        end
      end

      struct ApiResponse(T)
        getter ok : T?
        getter error : ApiErrorResponse?

        def initialize(@ok : T? = nil, @error : ApiErrorResponse? = nil)
        end

        def self.from_json_value(value : JSON::Any, & : JSON::Any -> T) : self
          if message = value.as_h["message"]?.try(&.as_s?)
            new(error: ApiErrorResponse.new(message))
          else
            new(ok: yield value)
          end
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = VOYAGEAI_API_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = VOYAGEAI_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["VOYAGE_API_KEY"]? || raise "VOYAGE_API_KEY not set"
          new(api_key, VOYAGEAI_API_BASE_URL)
        end

        def self.from_val(input : String) : self
          new(input, VOYAGEAI_API_BASE_URL)
        end

        def embedding_model(model : String, ndims : Int32? = nil) : EmbeddingModel
          dims = ndims || VoyageAI.model_dimensions_from_identifier(model) || 0
          EmbeddingModel.new(self, model, dims)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : EmbeddingModel
          EmbeddingModel.new(self, model, ndims)
        end

        def post_json(path : String, body : String) : HTTP::Client::Response
          headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Content-Type"  => "application/json",
            "Accept"        => "application/json",
          }
          HTTP::Client.exec("POST", build_uri(path), headers: headers, body: body)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end
      end

      struct EmbeddingModel
        include Crig::Embeddings::EmbeddingModel

        MAX_DOCUMENTS = 1024

        getter client : Client
        getter model : String
        getter ndims : Int32

        def initialize(@client : Client, @model : String, @ndims : Int32)
        end

        def self.make(client : Client, model : String, dims : Int32? = nil) : self
          resolved = dims || VoyageAI.model_dimensions_from_identifier(model) || 0
          new(client, model, resolved)
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

          response = @client.post_json("/embeddings", payload.to_json)
          body = response.body
          raise Crig::Embeddings::EmbeddingError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          envelope = ApiResponse(EmbeddingResponse).from_json_value(parsed) { |value| EmbeddingResponse.from_json(value.to_json) }
          if error = envelope.error
            raise Crig::Embeddings::EmbeddingError.new(error.message)
          end
          result = envelope.ok || raise Crig::Embeddings::EmbeddingError.new("VoyageAI response did not include a success payload")
          raise Crig::Embeddings::EmbeddingError.new("Response data length does not match input length") unless result.data.size == docs.size

          result.data.zip(docs).map do |embedding, document|
            Crig::Embeddings::Embedding.new(document, embedding.embedding)
          end
        end
      end

      struct Client
        include Crig::EmbeddingsClient(Crig::Providers::VoyageAI::EmbeddingModel)
      end
    end
  end
end
