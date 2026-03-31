require "http/client"

module Crig
  module Providers
    module Anthropic
      ANTHROPIC_API_BASE_URL   = "https://api.anthropic.com"
      ANTHROPIC_VERSION_LATEST = "2023-06-01"

      struct AnthropicExt
      end

      struct AnthropicBuilder
        getter anthropic_version : String
        getter anthropic_betas : Array(String)

        def initialize(
          @anthropic_version : String = ANTHROPIC_VERSION_LATEST,
          @anthropic_betas : Array(String) = [] of String,
        )
        end
      end

      struct AnthropicKey
        getter token : String

        def initialize(@token : String)
        end

        def to_header : Tuple(String, String)
          {"x-api-key", @token}
        end
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String
        getter anthropic_version : String
        getter anthropic_betas : Array(String)
        getter http_client : HTTP::Client?

        def initialize(
          @api_key : String? = nil,
          @base_url : String = ANTHROPIC_API_BASE_URL,
          @anthropic_version : String = ANTHROPIC_VERSION_LATEST,
          @anthropic_betas : Array(String) = [] of String,
          @http_client : HTTP::Client? = nil,
        )
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url, @anthropic_version, @anthropic_betas.dup, @http_client)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url, @anthropic_version, @anthropic_betas.dup, @http_client)
        end

        def anthropic_version(anthropic_version : String) : self
          self.class.new(@api_key, @base_url, anthropic_version, @anthropic_betas.dup, @http_client)
        end

        def anthropic_betas(anthropic_betas : Enumerable(String)) : self
          self.class.new(@api_key, @base_url, @anthropic_version, anthropic_betas.to_a, @http_client)
        end

        def anthropic_beta(anthropic_beta : String) : self
          updated_betas = @anthropic_betas.dup
          updated_betas << anthropic_beta
          self.class.new(@api_key, @base_url, @anthropic_version, updated_betas, @http_client)
        end

        def http_client(http_client : HTTP::Client) : self
          self.class.new(@api_key, @base_url, @anthropic_version, @anthropic_betas.dup, http_client)
        end

        def build : Client
          api_key = @api_key || raise "ANTHROPIC_API_KEY not set"
          Client.new(api_key, @base_url, @anthropic_version, @anthropic_betas, @http_client)
        end
      end

      struct Client
        getter api_key : AnthropicKey
        getter base_url : String
        getter anthropic_version : String
        getter anthropic_betas : Array(String)
        getter http_client : HTTP::Client?

        def initialize(
          @api_key : AnthropicKey,
          @base_url : String = ANTHROPIC_API_BASE_URL,
          @anthropic_version : String = ANTHROPIC_VERSION_LATEST,
          @anthropic_betas : Array(String) = [] of String,
          @http_client : HTTP::Client? = nil,
        )
        end

        def self.new(
          api_key : String,
          base_url : String = ANTHROPIC_API_BASE_URL,
          anthropic_version : String = ANTHROPIC_VERSION_LATEST,
          anthropic_betas : Array(String) = [] of String,
          http_client : HTTP::Client? = nil,
        ) : self
          new(AnthropicKey.new(api_key), base_url, anthropic_version, anthropic_betas, http_client)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["ANTHROPIC_API_KEY"]? || raise "ANTHROPIC_API_KEY not set"
          builder.api_key(api_key).build
        end

        def self.from_val(input : String) : self
          builder.api_key(input).build
        end

        def default_headers : HTTP::Headers
          headers = HTTP::Headers{
            "x-api-key"         => @api_key.token,
            "anthropic-version" => @anthropic_version,
            "content-type"      => "application/json",
            "accept"            => "application/json",
          }
          unless @anthropic_betas.empty?
            headers["anthropic-beta"] = @anthropic_betas.join(",")
          end
          headers
        end

        def post_json(path : String, body : String, headers : Hash(String, String) = {} of String => String) : HTTP::Client::Response
          all_headers = default_headers
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
