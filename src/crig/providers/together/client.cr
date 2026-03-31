require "http/client"

module Crig
  module Providers
    module Together
      struct TogetherExt
      end

      struct TogetherExtBuilder
      end

      struct ApiErrorResponse
        include JSON::Serializable

        getter error : String
        getter code : String

        def initialize(@error : String, @code : String)
        end

        def message : String
          "Code `#{@code}`: #{@error}"
        end
      end

      struct ApiResponse(T)
        getter ok : T?
        getter error : ApiErrorResponse?

        def initialize(@ok : T? = nil, @error : ApiErrorResponse? = nil)
        end

        def self.from_json_value(value : JSON::Any, & : JSON::Any -> T) : self
          hash = value.as_h
          if hash["error"]? && hash["code"]?
            new(error: ApiErrorResponse.from_json(value.to_json))
          else
            new(ok: yield value)
          end
        end
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = TOGETHER_AI_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          api_key = @api_key || raise "TOGETHER_API_KEY not set"
          Client.new(api_key, @base_url)
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = TOGETHER_AI_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = TOGETHER_AI_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["TOGETHER_API_KEY"]? || raise "TOGETHER_API_KEY not set"
          new(api_key)
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

        def post_json(path : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Content-Type"  => "application/json",
            "Accept"        => headers["Accept"]? || "application/json",
          }
          headers.each { |key, value| all_headers[key] = value }
          HTTP::Client.exec("POST", build_uri(path), headers: all_headers, body: body)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end
      end
    end
  end
end
