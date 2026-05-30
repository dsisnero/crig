require "http/client"

module Crig
  module Providers
    module OpenRouter
      struct OpenRouterExt
      end

      struct OpenRouterExtBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String
        getter app_title : String?
        getter app_url : String?
        getter app_categories : Array(String)?

        def initialize(
          @api_key : String? = nil,
          @base_url : String = OPENROUTER_API_BASE_URL,
          @app_title : String? = nil,
          @app_url : String? = nil,
          @app_categories : Array(String)? = nil,
        )
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url, @app_title, @app_url, @app_categories)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url, @app_title, @app_url, @app_categories)
        end

        def with_app_identity(title : String, url : String) : self
          self.class.new(@api_key, @base_url, title, url, @app_categories)
        end

        def with_app_categories(categories : Array(String)) : self
          self.class.new(@api_key, @base_url, @app_title, @app_url, categories.first(2))
        end

        def build : Client
          api_key = @api_key || raise "OPENROUTER_API_KEY not set"
          Client.new(api_key, @base_url, @app_title, @app_url, @app_categories)
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
          if message = value["message"]?.try(&.as_s?)
            new(error: ApiErrorResponse.new(message))
          else
            new(ok: yield value)
          end
        end
      end

      struct PromptTokensDetails
        include JSON::Serializable

        getter cached_tokens : Int32 = 0
        getter cache_write_tokens : Int32 = 0

        def initialize(@cached_tokens : Int32 = 0, @cache_write_tokens : Int32 = 0)
        end
      end

      struct Usage
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        @[JSON::Field(key: "prompt_tokens")]
        getter prompt_tokens : Int32
        @[JSON::Field(key: "completion_tokens")]
        getter completion_tokens : Int32 = 0
        @[JSON::Field(key: "total_tokens")]
        getter total_tokens : Int32
        getter cost : Float64 = 0.0
        @[JSON::Field(key: "prompt_tokens_details")]
        getter prompt_tokens_details : PromptTokensDetails?

        def initialize(
          @prompt_tokens : Int32,
          @total_tokens : Int32,
          @completion_tokens : Int32 = 0,
          @cost : Float64 = 0.0,
          @prompt_tokens_details : PromptTokensDetails? = nil,
        )
        end

        def token_usage : Crig::Completion::Usage?
          cached_input, cache_creation = if details = @prompt_tokens_details
                                           {details.cached_tokens.to_i64, details.cache_write_tokens.to_i64}
                                         else
                                           {0_i64, 0_i64}
                                         end
          Crig::Completion::Usage.new(
            input_tokens: @prompt_tokens.to_i64,
            output_tokens: @completion_tokens.to_i64,
            total_tokens: @total_tokens.to_i64,
            cached_input_tokens: cached_input,
            cache_creation_input_tokens: cache_creation,
          )
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String
        getter app_title : String?
        getter app_url : String?
        getter app_categories : Array(String)?

        def initialize(
          @api_key : Crig::BearerAuth,
          @base_url : String = OPENROUTER_API_BASE_URL,
          @app_title : String? = nil,
          @app_url : String? = nil,
          @app_categories : Array(String)? = nil,
        )
        end

        def self.new(api_key : String, base_url : String = OPENROUTER_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["OPENROUTER_API_KEY"]? || raise "OPENROUTER_API_KEY not set"
          new(api_key, OPENROUTER_API_BASE_URL)
        end

        def self.from_val(input : String) : self
          new(input, OPENROUTER_API_BASE_URL)
        end

        def post_json(path : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Content-Type"  => "application/json",
            "Accept"        => headers["Accept"]? || "application/json",
          }
          if title = @app_title
            all_headers["X-OpenRouter-Title"] = title
            if app_url = @app_url
              all_headers["HTTP-Referer"] = app_url
            end
          end
          if categories = @app_categories
            unless categories.empty?
              all_headers["X-OpenRouter-Categories"] = categories.join(",")
            end
          end
          headers.each { |key, value| all_headers[key] = value }
          HTTP::Client.exec("POST", build_uri(path), headers: all_headers, body: body)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end

        def completion_model(model : String) : Crig::Providers::OpenRouter::CompletionModel
          Crig::Providers::OpenRouter::CompletionModel.new(self, model)
        end

        def embedding_model(model : String) : Crig::Providers::OpenRouter::EmbeddingModel
          Crig::Providers::OpenRouter::EmbeddingModel.make(self, model, nil)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : Crig::Providers::OpenRouter::EmbeddingModel
          Crig::Providers::OpenRouter::EmbeddingModel.make(self, model, ndims)
        end
      end
    end
  end
end
