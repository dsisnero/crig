module Crig
  module Providers
    module Mistral
      struct MistralExt
      end

      struct MistralBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = MISTRAL_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          key = @api_key || raise "MISTRAL_API_KEY not set"
          Client.new(key, @base_url)
        end
      end

      struct PromptTokensDetails
        include JSON::Serializable

        @[JSON::Field(key: "cached_tokens")]
        getter cached_tokens : Int64

        def initialize(@cached_tokens : Int64 = 0_i64)
        end
      end

      struct Usage
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter completion_tokens : Int32
        getter prompt_tokens : Int32
        getter total_tokens : Int32
        @[JSON::Field(key: "num_cached_tokens")]
        getter num_cached_tokens : Int64?
        @[JSON::Field(key: "prompt_tokens_details")]
        getter prompt_tokens_details : PromptTokensDetails?
        @[JSON::Field(key: "prompt_token_details")]
        getter prompt_token_details_alias : PromptTokensDetails?

        def initialize(
          @completion_tokens : Int32,
          @prompt_tokens : Int32,
          @total_tokens : Int32,
          @num_cached_tokens : Int64? = nil,
          @prompt_tokens_details : PromptTokensDetails? = nil,
          @prompt_token_details_alias : PromptTokensDetails? = nil,
        )
        end

        def cached_tokens : Int64
          if details = @prompt_tokens_details || @prompt_token_details_alias
            details.cached_tokens
          elsif cached = @num_cached_tokens
            cached
          else
            0_i64
          end
        end

        def token_usage : Crig::Completion::Usage?
          Crig::Completion::Usage.new(
            input_tokens: @prompt_tokens.to_i64,
            output_tokens: @completion_tokens.to_i64,
            total_tokens: @total_tokens.to_i64,
            cached_input_tokens: cached_tokens,
          )
        end

        def to_s(io : IO) : Nil
          io << "Prompt tokens: " << @prompt_tokens << " Total tokens: " << @total_tokens
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

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = MISTRAL_API_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = MISTRAL_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["MISTRAL_API_KEY"]? || raise "MISTRAL_API_KEY not set"
          new(api_key)
        end

        def self.from_val(input : String) : self
          new(input)
        end

        def default_headers(accept : String = "application/json") : HTTP::Headers
          HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Content-Type"  => "application/json",
            "Accept"        => accept,
          }
        end

        def post_json(path : String, body : String, accept : String = "application/json") : HTTP::Client::Response
          HTTP::Client.exec("POST", build_uri(path), headers: default_headers(accept), body: body)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def embedding_model(model : String, ndims : Int32 = 0) : EmbeddingModel
          EmbeddingModel.new(self, model, ndims)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : EmbeddingModel
          EmbeddingModel.new(self, model, ndims)
        end

        def transcription_model(model : String) : TranscriptionModel
          TranscriptionModel.new(self, model)
        end
      end
    end
  end
end
