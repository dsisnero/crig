module Crig
  module Client
    class ClientBuilderError < Exception
      def self.http_error(message : String) : self
        new("reqwest error: #{message}")
      end

      def self.invalid_property(property : String) : self
        new("invalid property: #{property}")
      end
    end

    enum Transport : UInt8
      Http
      Sse
      NdJson
    end

    module ApiKey
      def into_header : {String, String}?
        nil
      end
    end

    struct BearerAuth
      include ApiKey

      getter token : String

      def initialize(@token : String)
      end

      def self.from(value) : self
        new(value.to_s)
      end

      def into_header : {String, String}
        {"Authorization", "Bearer #{@token}"}
      end
    end

    struct Nothing
      include ApiKey

      def self.try_from(value : String) : self
        raise "Tried to create a Nothing from a string - this should not happen, please file an issue"
      end
    end

    struct Capable(M)
      def capable? : Bool
        true
      end
    end

    module Capability
      abstract def capable? : Bool
    end

    struct NeedsApiKey
      include ApiKey
    end

    module ProviderClient(I)
    end

    module DebugExt
      def fields : Array({String, String})
        [] of {String, String}
      end
    end

    module Provider(B)
      def build_uri(base_url : String, path : String, transport : Transport) : String
        _ = transport
        trimmed = path.lstrip('/')
        return trimmed if base_url.empty?
        "#{base_url.rstrip('/')}/#{trimmed}"
      end
    end

    module Capabilities
      abstract def completion_capability : Bool
      abstract def embeddings_capability : Bool
      abstract def transcription_capability : Bool
      abstract def model_listing_capability : Bool
      abstract def image_generation_capability : Bool
      abstract def audio_generation_capability : Bool
    end

    module ProviderBuilder(E, A)
    end

    struct Client(Ext, H)
      getter base_url : String
      getter headers : Hash(String, String)
      getter http_client : H?
      getter ext : Ext

      def initialize(
        @ext : Ext,
        @base_url : String = "",
        @headers : Hash(String, String) = {} of String => String,
        @http_client : H? = nil,
      )
      end

      def self.builder(ext : Ext, base_url : String = "") forall Ext
        ClientBuilder(Ext, NeedsApiKey, Nil).new(
          ext,
          base_url: base_url,
          api_key: NeedsApiKey.new,
        )
      end

      def self.new(ext : Ext, api_key, base_url : String = "") forall Ext
        builder(ext, base_url).api_key(api_key).build
      end

      def with_ext(new_ext : NewExt) : Client(NewExt, H) forall NewExt
        Client(NewExt, H).new(
          new_ext,
          base_url: @base_url,
          headers: @headers,
          http_client: @http_client,
        )
      end

      def post(path : String) : RequestBuilder
        request_builder("POST", path, Transport::Http)
      end

      def post_sse(path : String) : RequestBuilder
        request_builder("POST", path, Transport::Sse)
      end

      def get(path : String) : RequestBuilder
        request_builder("GET", path, Transport::Http)
      end

      def get_sse(path : String) : RequestBuilder
        request_builder("GET", path, Transport::Sse)
      end

      private def request_builder(method : String, path : String, transport : Transport) : RequestBuilder
        uri = if @ext.responds_to?(:build_uri)
                @ext.build_uri(@base_url, path, transport)
              else
                trimmed = path.lstrip('/')
                @base_url.empty? ? trimmed : "#{@base_url.rstrip('/')}/#{trimmed}"
              end

        RequestBuilder.new(method, uri, @headers.dup)
      end
    end

    struct RequestBuilder
      getter method : String
      getter uri : String
      getter headers : Hash(String, String)
      getter body_value : String?

      def initialize(
        @method : String,
        @uri : String,
        @headers : Hash(String, String) = {} of String => String,
        @body_value : String? = nil,
      )
      end

      def body(value) : self
        self.class.new(@method, @uri, @headers, value.to_s)
      end
    end

    struct ClientBuilder(Ext, ApiKeyType, H)
      getter base_url : String
      getter api_key : ApiKeyType
      getter headers : Hash(String, String)
      getter http_client : H?
      getter ext : Ext

      def initialize(
        ext : Ext,
        api_key : ApiKeyType,
        base_url : String = "",
        headers : Hash(String, String) = {} of String => String,
        http_client : H? = nil,
      )
        @ext = ext
        @api_key = api_key
        @base_url = base_url
        @headers = headers
        @http_client = http_client
      end

      def api_key(api_key : NewApiKey) : ClientBuilder(Ext, NewApiKey, H) forall NewApiKey
        ClientBuilder(Ext, NewApiKey, H).new(
          @ext,
          api_key,
          @base_url,
          @headers,
          @http_client,
        )
      end

      def base_url(base_url : String) : self
        self.class.new(@ext, @api_key, base_url, @headers, @http_client)
      end

      def http_client(http_client : NewHttpClient) : ClientBuilder(Ext, ApiKeyType, NewHttpClient) forall NewHttpClient
        ClientBuilder(Ext, ApiKeyType, NewHttpClient).new(
          @ext,
          @api_key,
          @base_url,
          @headers,
          http_client,
        )
      end

      def http_headers(headers : Hash(String, String)) : self
        self.class.new(@ext, @api_key, @base_url, headers, @http_client)
      end

      def ext : Ext
        @ext
      end

      def build : Client(Ext, H)
        merged_headers = @headers.dup
        if header = @api_key.into_header
          merged_headers[header[0]] = header[1]
        end

        Client(Ext, H).new(
          @ext,
          base_url: @base_url,
          headers: merged_headers,
          http_client: @http_client,
        )
      end
    end
  end

  alias ApiKey = Client::ApiKey
  alias BearerAuth = Client::BearerAuth
  alias Capabilities = Client::Capabilities
  alias Capability = Client::Capability
  alias Capable = Client::Capable
  alias ClientBuilderError = Client::ClientBuilderError
  alias DebugExt = Client::DebugExt
  alias NeedsApiKey = Client::NeedsApiKey
  alias Nothing = Client::Nothing
  alias ProviderClientBuilder = Client::ClientBuilder
  alias ProviderHttpClient = Client::Client
  alias Provider = Client::Provider
  alias ProviderBuilder = Client::ProviderBuilder
  alias ProviderClient = Client::ProviderClient
  alias Transport = Client::Transport
end
