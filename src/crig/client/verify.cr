module Crig
  module Client
    class VerifyError < Exception
      getter provider_response : ProviderResponseError?

      def initialize(message : String, @provider_response : ProviderResponseError? = nil)
        super(message)
      end

      def self.invalid_authentication : self
        new("invalid authentication")
      end

      def self.provider_error(message : String) : self
        new("provider error: #{message}")
      end

      def self.http_error(message : String) : self
        new("http error: #{message}")
      end

      def self.from_http_response(status : Int32, body : String) : self
        pr = ProviderResponseError.new(status: status, body: body)
        if 200 <= status && status < 300
          new("ProviderResponseError", provider_response: pr)
        else
          new("http error: #{status} #{body}", provider_response: pr)
        end
      end

      def self.from_provider_body(body : String) : self
        new("ProviderResponseError", provider_response: ProviderResponseError.without_status(body))
      end

      include Crig::ProviderResponseHelpers

      def provider_response_body : String?
        @provider_response.try(&.body)
      end

      def provider_response_status : Int32?
        @provider_response.try(&.status)
      end
    end

    module VerifyClient
      abstract def verify : Nil

      def verify_async : Channel(Crig::Concurrency::Result(Nil))
        Crig::Concurrency.run do
          verify
        end
      end
    end

    module VerifyClientDyn
      abstract def verify : Nil

      def verify_async : Channel(Crig::Concurrency::Result(Nil))
        Crig::Concurrency.run do
          verify
        end
      end
    end
  end
end
