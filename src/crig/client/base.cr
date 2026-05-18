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

    module Capability
      abstract def capable? : Bool
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
      include Capability

      def capable? : Bool
        false
      end

      def self.try_from(value : String) : self
        raise "Tried to create a Nothing from a string - this should not happen, please file an issue"
      end
    end

    # Errors returned while constructing provider clients from environment
    # variables or explicit input.
    class ProviderClientError < Exception
      enum Kind
        EnvironmentVariable
        Http
        InvalidConfiguration
      end

      getter kind : Kind
      getter var_name : String?
      getter http_error : HttpClient::Error?
      getter detail : String?

      def initialize(
        message : String,
        @kind : Kind,
        @var_name : String? = nil,
        @http_error : HttpClient::Error? = nil,
        @detail : String? = nil,
      )
        super(message)
      end

      def self.environment_variable(name : String, message : String) : self
        new("environment variable '#{name}' is not set or is invalid: #{message}", Kind::EnvironmentVariable, var_name: name)
      end

      def self.http(error : HttpClient::Error) : self
        new(error.message || "http error", Kind::Http, http_error: error)
      end

      def self.invalid_configuration(message : String) : self
        new(message, Kind::InvalidConfiguration, detail: message)
      end
    end

    # Read a required environment variable for provider client construction.
    def self.required_env_var(name : String) : String | ProviderClientError
      ENV[name]? || ProviderClientError.environment_variable(name, "not set")
    end

    # Read an optional environment variable for provider client construction.
    # Returns nil when the variable is not present.
    def self.optional_env_var(name : String) : String? | ProviderClientError
      if ENV.has_key?(name)
        ENV[name]
      end
    end

    struct Capable(M)
      include Capability

      def capable? : Bool
        true
      end
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
      abstract def build_uri(base_url : String, path : String, transport : Transport) : String
      abstract def with_custom(request : RequestBuilder) : RequestBuilder

      abstract def verify_path : String
      abstract def builder_type : B.class
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
      abstract def base_url : String
      abstract def build(builder : ClientBuilder(self, A, H)) : E forall H

      def finish(builder : ClientBuilder(self, A, H)) : ClientBuilder(self, A, H) forall H
        builder
      end
    end

    struct Client(Ext, H)
      include HttpClient::HttpClientExt

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

      def send(req : HTTP::Request, body : Bytes = Bytes.empty) : HttpClient::Result(HttpClient::Response(HttpClient::LazyBytes), HttpClient::Error)
        # Add content-type header if not present
        unless req.headers.has_key?("Content-Type")
          req.headers["Content-Type"] = "application/json"
        end

        # Merge client headers
        @headers.each do |key, value|
          req.headers[key] = value
        end

        if http_client = @http_client
          http_client.send(req, body)
        else
          HttpClient::Result(HttpClient::Response(HttpClient::LazyBytes), HttpClient::Error).err(
            HttpClient::Error.new(HttpClient::Error::Kind::Instance, "No HTTP client configured")
          )
        end
      end

      def send_multipart(req : HTTP::Request, form : HttpClient::MultipartForm) : HttpClient::Result(HttpClient::Response(HttpClient::LazyBytes), HttpClient::Error)
        # Merge client headers
        @headers.each do |key, value|
          req.headers[key] = value
        end

        if http_client = @http_client
          http_client.send_multipart(req, form)
        else
          HttpClient::Result(HttpClient::Response(HttpClient::LazyBytes), HttpClient::Error).err(
            HttpClient::Error.new(HttpClient::Error::Kind::Instance, "No HTTP client configured")
          )
        end
      end

      def send_streaming(req : HTTP::Request, body : Bytes = Bytes.empty) : HttpClient::Result(HttpClient::StreamingResponse, HttpClient::Error)
        # Add content-type header if not present
        unless req.headers.has_key?("Content-Type")
          req.headers["Content-Type"] = "application/json"
        end

        # Merge client headers
        @headers.each do |key, value|
          req.headers[key] = value
        end

        if http_client = @http_client
          http_client.send_streaming(req, body)
        else
          HttpClient::Result(HttpClient::StreamingResponse, HttpClient::Error).err(
            HttpClient::Error.new(HttpClient::Error::Kind::Instance, "No HTTP client configured")
          )
        end
      end

      private def request_builder(method : String, path : String, transport : Transport) : RequestBuilder
        uri = @ext.build_uri(@base_url, path, transport)

        builder = RequestBuilder.new(method, uri, @headers.dup)
        @ext.with_custom(builder)
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

      def with_header(key : String, value : String) : self
        new_headers = @headers.dup
        new_headers[key] = value
        self.class.new(@method, @uri, new_headers, @body_value)
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
