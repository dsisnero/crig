module Crig
  module Providers
    module Cohere
      COHERE_API_BASE_URL = "https://api.cohere.ai"

      struct CohereExt
      end

      struct CohereBuilder
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
          if message = value["message"]?.try(&.as_s?)
            new(error: ApiErrorResponse.new(message))
          else
            new(ok: yield value)
          end
        end
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(
          @api_key : String? = nil,
          @base_url : String = COHERE_API_BASE_URL,
        )
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          api_key = @api_key || raise "COHERE_API_KEY not set"
          Client.new(api_key, @base_url)
        end
      end

      struct Client
        getter api_key : String
        getter base_url : String

        def initialize(@api_key : String, @base_url : String = COHERE_API_BASE_URL)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["COHERE_API_KEY"]? || raise "COHERE_API_KEY not set"
          new(api_key)
        end

        def self.from_val(input : String) : self
          new(input)
        end

        def default_headers : HTTP::Headers
          HTTP::Headers{
            "authorization" => "Bearer #{@api_key}",
            "content-type"  => "application/json",
            "accept"        => "application/json",
          }
        end

        def post_json(path : String, body : String) : HTTP::Client::Response
          HTTP::Client.exec("POST", build_uri(path), headers: default_headers, body: body)
        end

        def get(path : String) : HTTP::Client::Response
          HTTP::Client.get(build_uri(path), headers: default_headers)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end

        def embedding_model(model : String, input_type : String)
          ndims = Cohere.model_dimensions_from_identifier(model) || 0
          EmbeddingModel.new(self, model, input_type, ndims)
        end

        def embeddings(model : String, input_type : String) : Crig::Embeddings::EmbeddingsBuilderInitializer(EmbeddingModel)
          Crig::Embeddings::EmbeddingsBuilderInitializer(EmbeddingModel).new(
            embedding_model(model, input_type)
          )
        end

        def embeddings(type : D.class, model : String, input_type : String) : Crig::Embeddings::EmbeddingsBuilderInitializer(EmbeddingModel) forall D
          Crig::Embeddings::EmbeddingsBuilderInitializer(EmbeddingModel).new(
            embedding_model(model, input_type)
          )
        end

        def embedding_model_with_ndims(model : String, input_type : String, ndims : Int32)
          EmbeddingModel.new(self, model, input_type, ndims)
        end

        def embeddings_with_ndims(model : String, input_type : String, ndims : Int32) : Crig::Embeddings::EmbeddingsBuilderInitializer(EmbeddingModel)
          Crig::Embeddings::EmbeddingsBuilderInitializer(EmbeddingModel).new(
            embedding_model_with_ndims(model, input_type, ndims)
          )
        end

        def embeddings_with_ndims(type : D.class, model : String, input_type : String, ndims : Int32) : Crig::Embeddings::EmbeddingsBuilderInitializer(EmbeddingModel) forall D
          Crig::Embeddings::EmbeddingsBuilderInitializer(EmbeddingModel).new(
            embedding_model_with_ndims(model, input_type, ndims)
          )
        end

        def completion_model(model : String) : Crig::Providers::Cohere::CompletionModel
          CompletionModel.new(self, model)
        end
      end
    end
  end
end
