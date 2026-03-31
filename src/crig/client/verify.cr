module Crig
  module Client
    class VerifyError < Exception
      def self.invalid_authentication : self
        new("invalid authentication")
      end

      def self.provider_error(message : String) : self
        new("provider error: #{message}")
      end

      def self.http_error(message : String) : self
        new("http error: #{message}")
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
