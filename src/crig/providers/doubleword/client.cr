require "http/client"

module Crig
  module Providers
    module Doubleword
      DOUBLEWORD_API_BASE_URL = "https://api.doubleword.ai/v1"

      struct DoublewordExt
      end

      struct DoublewordExtBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = DOUBLEWORD_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          key = @api_key || raise "DOUBLEWORD_API_KEY not set"
          Client.new(key, @base_url)
        end
      end

      struct ApiErrorResponse
        include JSON::Serializable

        getter message : String
        getter type : String?
        getter code : String?

        def initialize(@message : String, @type : String? = nil, @code : String? = nil)
        end
      end

      struct ApiResponse(T)
        getter ok : T?
        getter error : ApiErrorResponse?

        def initialize(@ok : T? = nil, @error : ApiErrorResponse? = nil)
        end

        def self.from_json_value(value : JSON::Any, & : JSON::Any -> T) : self
          if message = value["error"]?.try(&.as_h?).try(&.["message"]?.try(&.as_s?))
            error = value["error"].as_h
            new(error: ApiErrorResponse.new(message, error["type"]?.try(&.as_s?), error["code"]?.try(&.as_s?)))
          else
            new(ok: yield value)
          end
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = DOUBLEWORD_API_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = DOUBLEWORD_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["DOUBLEWORD_API_KEY"]? || raise "DOUBLEWORD_API_KEY not set"
          base_url = ENV["DOUBLEWORD_BASE_URL"]? || DOUBLEWORD_API_BASE_URL
          new(api_key, base_url)
        end

        def self.from_val(input : String) : self
          new(input)
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def embedding_model(model : String, ndims : Int32? = nil) : EmbeddingModel
          EmbeddingModel.new(self, model, ndims || 0)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : EmbeddingModel
          EmbeddingModel.new(self, model, ndims)
        end

        def post_json(path : String, body : String, accept : String = "application/json") : HTTP::Client::Response
          HTTP::Client.exec(
            "POST",
            build_uri(path),
            headers: HTTP::Headers{
              "Authorization" => "Bearer #{@api_key.token}",
              "Content-Type"  => "application/json",
              "Accept"        => accept,
            },
            body: body,
          )
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end
      end
    end
  end
end
