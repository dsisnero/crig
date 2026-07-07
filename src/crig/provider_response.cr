module Crig
  class ProviderResponseError
    include JSON::Serializable

    getter status : Int32?
    getter body : String

    def initialize(@status : Int32? = nil, @body : String = "")
    end

    def self.without_status(body : String) : self
      new(status: nil, body: body)
    end

    def to_s(io : IO) : Nil
      if s = @status
        io << "status " << s << ": " << @body
      else
        io << @body
      end
    end
  end

  module ProviderResponseHelpers
    # Returns the raw provider response body when available via ProviderResponse or HttpError.
    abstract def provider_response_body : String?

    # Parses the provider response body as JSON.
    def provider_response_json : JSON::Any?
      body = provider_response_body
      return nil if body.nil? || body.empty?
      JSON.parse(body)
    rescue JSON::ParseException
      nil
    end

    # Returns the HTTP status code when preserved.
    abstract def provider_response_status : Int32?
  end
end
