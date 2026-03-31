require "http/client"
require "http/headers"
require "http/request"
require "./http_client/multipart"
require "./http_client/retry"
require "./http_client/sse"

module Crig
  module HttpClient
    class Error < Exception
      enum Kind
        Protocol
        InvalidStatusCode
        InvalidStatusCodeWithMessage
        InvalidHeaderValue
        NoHeaders
        StreamEnded
        InvalidContentType
        Instance
      end

      getter kind : Kind
      getter status_code : Int32?
      getter detail : String?
      getter source : Exception?

      def initialize(
        @kind : Kind,
        message : String,
        @status_code : Int32? = nil,
        @detail : String? = nil,
        @source : Exception? = nil,
      )
        super(message)
      end

      def self.protocol(message : String) : self
        new(Kind::Protocol, "Http error: #{message}", detail: message)
      end

      def self.invalid_status_code(status_code : Int32) : self
        new(Kind::InvalidStatusCode, "Invalid status code: #{status_code}", status_code: status_code)
      end

      def self.invalid_status_code_with_message(status_code : Int32, message : String) : self
        new(
          Kind::InvalidStatusCodeWithMessage,
          "Invalid status code #{status_code} with message: #{message}",
          status_code: status_code,
          detail: message
        )
      end

      def self.invalid_header_value(message : String) : self
        new(Kind::InvalidHeaderValue, "Header value outside of legal range: #{message}", detail: message)
      end

      def self.no_headers : self
        new(Kind::NoHeaders, "Request in error state, cannot access headers")
      end

      def self.stream_ended : self
        new(Kind::StreamEnded, "Stream ended")
      end

      def self.invalid_content_type(content_type : String) : self
        new(
          Kind::InvalidContentType,
          "Invalid content type was returned: #{content_type.inspect}",
          detail: content_type
        )
      end

      def self.instance(error : Exception) : self
        new(
          Kind::Instance,
          "Http client error: #{error.message || error.class.name}",
          detail: error.message || error.class.name,
          source: error
        )
      end
    end

    struct Result(T, E)
      getter value : T?
      getter error : E?

      def initialize(@value : T? = nil, @error : E? = nil)
      end

      def self.ok(value : T) : self
        new(value: value)
      end

      def self.err(error : E) : self
        new(error: error)
      end

      def unwrap : T
        if error = @error
          raise error if error.is_a?(Exception)
          raise "http client result missing value: #{error}"
        end
        {% if T == Nil %}
          return nil
        {% end %}
        @value || raise "http client result missing value"
      end
    end

    class Stream(T)
      def initialize(@channel : Channel(T))
      end

      def receive : T
        @channel.receive
      end

      def receive? : T?
        @channel.receive?
      end
    end

    class LazyBody(T)
      getter stream : Stream(Result(T, Error))

      def initialize(@stream : Stream(Result(T, Error)))
      end

      def initialize(channel : Channel(Result(T, Error)))
        @stream = Stream(Result(T, Error)).new(channel)
      end

      def receive : Result(T, Error)
        @stream.receive
      end

      def receive? : Result(T, Error)?
        @stream.receive?
      end
    end

    alias LazyBytes = LazyBody(Bytes)

    class Response(T)
      getter status_code : Int32
      getter headers : HTTP::Headers
      getter body : T

      def initialize(
        @body : T,
        @status_code : Int32 = 200,
        headers : HTTP::Headers? = nil,
      )
        @headers = headers || HTTP::Headers.new
      end
    end

    class RequestBuilder
      getter method : String
      getter resource : String
      getter body : Bytes?
      getter version : String

      def initialize(
        @method : String,
        @resource : String,
        @headers : HTTP::Headers? = HTTP::Headers.new,
        @body : Bytes? = nil,
        @version : String = "HTTP/1.1",
      )
      end

      def headers_mut : HTTP::Headers?
        @headers
      end

      def build : Result(HTTP::Request, Error)
        Result(HTTP::Request, Error).ok(
          HTTP::Request.new(@method, @resource, @headers || HTTP::Headers.new, @body, @version)
        )
      rescue ex
        Result(HTTP::Request, Error).err(Error.protocol(ex.message || ex.class.name))
      end
    end

    class StreamingResponse
      getter status_code : Int32
      getter headers : HTTP::Headers
      getter stream : Stream(Result(Bytes, Error))

      def initialize(
        @stream : Stream(Result(Bytes, Error)),
        @status_code : Int32 = 200,
        headers : HTTP::Headers? = nil,
      )
        @headers = headers || HTTP::Headers{"Content-Type" => "text/event-stream"}
      end

      def initialize(
        channel : Channel(Result(Bytes, Error)),
        @status_code : Int32 = 200,
        headers : HTTP::Headers? = nil,
      )
        @stream = Stream(Result(Bytes, Error)).new(channel)
        @headers = headers || HTTP::Headers{"Content-Type" => "text/event-stream"}
      end

      def receive : Result(Bytes, Error)
        @stream.receive
      end

      def receive? : Result(Bytes, Error)?
        @stream.receive?
      end
    end

    struct NoBody
      def to_slice : Bytes
        Bytes.empty
      end
    end

    def self.text(response : Response(LazyBody(Array(UInt8)))) : String
      result = response.body.receive
      decode_text(result.unwrap)
    end

    def self.decode_text(bytes : Bytes) : String
      string = String.new(bytes)
      string.valid_encoding? ? string : string.scrub
    end

    def self.decode_text(bytes : Array(UInt8)) : String
      decode_text(Bytes.new(bytes.size) { |index| bytes[index] })
    end

    def self.make_auth_header(key : String) : Result({String, String}, Error)
      Result({String, String}, Error).ok({"Authorization", "Bearer #{key}"})
    rescue ex
      Result({String, String}, Error).err(Error.invalid_header_value(ex.message || ex.class.name))
    end

    def self.bearer_auth_header(headers : HTTP::Headers, key : String) : Result(Nil, Error)
      header = make_auth_header(key).unwrap
      headers[header[0]] = header[1]
      Result(Nil, Error).ok(nil)
    end

    def self.bearer_auth_header(headers : Hash(String, String), key : String) : Result(Nil, Error)
      header = make_auth_header(key).unwrap
      headers[header[0]] = header[1]
      Result(Nil, Error).ok(nil)
    end

    def self.with_bearer_auth(req : HTTP::Request, auth : String) : Result(HTTP::Request, Error)
      bearer_auth_header(req.headers, auth)
      Result(HTTP::Request, Error).ok(req)
    end

    def self.with_bearer_auth(req : RequestBuilder, auth : String) : Result(RequestBuilder, Error)
      headers = req.headers_mut || return Result(RequestBuilder, Error).err(Error.no_headers)
      bearer_auth_header(headers, auth)
      Result(RequestBuilder, Error).ok(req)
    end

    module HttpClientExt
      abstract def send(req : HTTP::Request, body : Bytes = Bytes.empty) : Result(Response(LazyBytes), Error)
      abstract def send_multipart(req : HTTP::Request, form : MultipartForm) : Result(Response(LazyBytes), Error)
      abstract def send_streaming(req : HTTP::Request, body : Bytes = Bytes.empty) : Result(StreamingResponse, Error)
    end

    class MockStreamingClient
      include HttpClientExt

      getter sent_requests : Array({String, String})
      getter response_body : Bytes
      getter response_status_code : Int32
      getter response_headers : HTTP::Headers
      getter stream_chunks : Array(Bytes)
      getter streaming_status_code : Int32
      getter streaming_headers : HTTP::Headers

      def initialize(
        @response_body : Bytes = Bytes.empty,
        @response_status_code : Int32 = 200,
        response_headers : HTTP::Headers? = nil,
        @stream_chunks : Array(Bytes) = [] of Bytes,
        @streaming_status_code : Int32 = 200,
        streaming_headers : HTTP::Headers? = nil,
      )
        @sent_requests = [] of {String, String}
        @response_headers = response_headers || HTTP::Headers.new
        @streaming_headers = streaming_headers || HTTP::Headers{"Content-Type" => "text/event-stream"}
      end

      def send(req : HTTP::Request, body : Bytes = Bytes.empty) : Result(Response(LazyBytes), Error)
        @sent_requests << {req.method, req.resource}
        _ = body
        regular_response_result
      end

      def send_multipart(req : HTTP::Request, form : MultipartForm) : Result(Response(LazyBytes), Error)
        @sent_requests << {req.method, req.resource}
        _ = form
        regular_response_result
      end

      private def regular_response_result : Result(Response(LazyBytes), Error)
        unless (200..299).includes?(@response_status_code)
          return Result(Response(LazyBytes), Error).err(
            Error.invalid_status_code_with_message(@response_status_code, HttpClient.decode_text(@response_body))
          )
        end

        channel = Channel(Result(Bytes, Error)).new(1)
        spawn do
          channel.send(Result(Bytes, Error).ok(@response_body))
          channel.close
        end
        Result(Response(LazyBytes), Error).ok(
          Response.new(LazyBody(Bytes).new(channel), @response_status_code, @response_headers.dup)
        )
      end

      def send_streaming(req : HTTP::Request, body : Bytes = Bytes.empty) : Result(StreamingResponse, Error)
        @sent_requests << {req.method, req.resource}
        _ = body
        channel = Channel(Result(Bytes, Error)).new
        spawn do
          @stream_chunks.each do |chunk|
            channel.send(Result(Bytes, Error).ok(chunk))
          end
          channel.close
        end
        Result(StreamingResponse, Error).ok(
          StreamingResponse.new(channel, @streaming_status_code, @streaming_headers.dup)
        )
      end
    end
  end

  alias HttpClientError = HttpClient::Error
end
