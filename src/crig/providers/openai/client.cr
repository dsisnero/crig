require "http/client"

module Crig
  module Providers
    module OpenAI
      struct OpenAIResponsesExt
      end

      struct OpenAIResponsesExtBuilder
      end

      struct OpenAICompletionsExt
      end

      struct OpenAICompletionsExtBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = OPENAI_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          api_key = @api_key || raise "OPENAI_API_KEY not set"
          Client.new(api_key, @base_url)
        end
      end

      struct CompletionsClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = OPENAI_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : CompletionsClient
          api_key = @api_key || raise "OPENAI_API_KEY not set"
          CompletionsClient.new(api_key, @base_url)
        end
      end

      struct ApiErrorResponse
        include JSON::Serializable

        getter message : String

        def initialize(@message : String)
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = OPENAI_API_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = OPENAI_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["OPENAI_API_KEY"]? || raise "OPENAI_API_KEY not set"
          base_url = ENV["OPENAI_BASE_URL"]? || OPENAI_API_BASE_URL
          new(api_key, base_url)
        end

        def self.from_val(input : Crig::BearerAuth) : self
          new(input, OPENAI_API_BASE_URL)
        end

        def completions_api : CompletionsClient
          CompletionsClient.new(@api_key, @base_url)
        end

        def embedding_model(model : String) : Crig::Providers::OpenAI::EmbeddingModel
          Crig::Providers::OpenAI::EmbeddingModel.make(self, model, nil)
        end

        def embedding_model_with_ndims(model : String, ndims : Int32) : Crig::Providers::OpenAI::EmbeddingModel
          Crig::Providers::OpenAI::EmbeddingModel.make(self, model, ndims)
        end

        def post_json(path : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Content-Type"  => "application/json",
            "Accept"        => "application/json",
          }
          headers.each { |key, value| all_headers[key] = value }
          HTTP::Client.exec("POST", build_uri(path), headers: all_headers, body: body)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end
      end

      struct CompletionsClient
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = OPENAI_API_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = OPENAI_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : CompletionsClientBuilder
          CompletionsClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["OPENAI_API_KEY"]? || raise "OPENAI_API_KEY not set"
          base_url = ENV["OPENAI_BASE_URL"]? || OPENAI_API_BASE_URL
          new(api_key, base_url)
        end

        def self.from_val(input : Crig::BearerAuth) : self
          new(input, OPENAI_API_BASE_URL)
        end

        def completion_model(model : String) : Crig::Providers::OpenAI::CompletionModel
          Crig::Providers::OpenAI::CompletionModel.new(self, model)
        end

        def responses_api : Client
          Client.new(@api_key, @base_url)
        end

        def post_json(path : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Content-Type"  => "application/json",
            "Accept"        => "application/json",
          }
          headers.each { |key, value| all_headers[key] = value }
          HTTP::Client.exec("POST", build_uri(path), headers: all_headers, body: body)
        end

        private def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end
      end
    end
  end
end
