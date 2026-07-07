module Crig
  class RerankError < Exception
    enum Kind
      HttpError
      JsonError
      UrlError
      ResponseError
      ProviderError
      ProviderResponse
    end

    getter kind : Kind
    getter source_error : Exception?
    getter provider_response : ProviderResponseError?

    def initialize(
      message : String,
      @kind : Kind = Kind::ResponseError,
      @source_error : Exception? = nil,
      @provider_response : ProviderResponseError? = nil,
    )
      super(message)
    end

    def self.http_error(error : Exception) : self
      new("HttpError: #{error.message || error.class.name}", Kind::HttpError, source_error: error)
    end

    def self.json_error(error : Exception) : self
      new("JsonError: #{error.message || error.class.name}", Kind::JsonError, source_error: error)
    end

    def self.url_error(error : Exception) : self
      new("UrlError: #{error.message || error.class.name}", Kind::UrlError, source_error: error)
    end

    def self.response_error(message : String) : self
      new("ResponseError: #{message}", Kind::ResponseError)
    end

    def self.provider_error(message : String) : self
      new("ProviderError: #{message}", Kind::ProviderError)
    end

    def self.from_http_response(status : Int32, body : String) : self
      if 200 <= status && status < 300
        new("ProviderResponseError", Kind::ProviderResponse, provider_response: ProviderResponseError.new(status: status, body: body))
      else
        new("HttpError: #{status} #{body}", Kind::HttpError)
      end
    end

    def self.from_provider_body(body : String) : self
      new("ProviderResponseError", Kind::ProviderResponse, provider_response: ProviderResponseError.without_status(body))
    end

    include ProviderResponseHelpers

    def provider_response_body : String?
      case @kind
      when Kind::ProviderResponse
        @provider_response.try(&.body)
      else
        nil
      end
    end

    def provider_response_status : Int32?
      case @kind
      when Kind::ProviderResponse
        @provider_response.try(&.status)
      else
        nil
      end
    end
  end

  struct RerankResult
    include JSON::Serializable

    getter index : Int32
    getter document : String?
    getter relevance_score : Float64

    def initialize(@index : Int32, @relevance_score : Float64, @document : String? = nil)
    end
  end

  struct RerankResponse
    getter results : Array(RerankResult)
    getter model : String
    getter usage : Completion::Usage

    def initialize(@results : Array(RerankResult), @model : String, @usage : Completion::Usage)
    end
  end

  module RerankModel
    abstract def rerank(query : String, documents : Array(String)) : RerankResponse
  end
end
