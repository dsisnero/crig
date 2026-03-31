require "http/client"

module Crig
  module Providers
    module XAI
      XAI_BASE_URL = "https://api.x.ai"

      struct XAiExt
      end

      struct XAiExtBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = XAI_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          api_key = @api_key || raise "XAI_API_KEY not set"
          Client.new(api_key, @base_url)
        end
      end

      struct Client
        getter api_key : Crig::BearerAuth
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @base_url : String = XAI_BASE_URL)
        end

        def self.new(api_key : String, base_url : String = XAI_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["XAI_API_KEY"]? || raise "XAI_API_KEY not set"
          new(api_key, XAI_BASE_URL)
        end

        def self.from_val(input : String) : self
          new(input, XAI_BASE_URL)
        end

        def completion_model(model : String) : Crig::Providers::XAI::CompletionModel
          Crig::Providers::XAI::CompletionModel.new(self, model)
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
