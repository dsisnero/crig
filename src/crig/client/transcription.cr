module Crig
  module Client
    module TranscriptionClient(M)
      abstract def transcription_model(model : String) : M
    end

    module TranscriptionClientDyn
      abstract def transcription_model(model : String) : Crig::TranscriptionModelDyn
    end

    struct TranscriptionModelHandle
      include Crig::TranscriptionModel

      getter inner : Crig::TranscriptionModelDyn

      def initialize(@inner : Crig::TranscriptionModelDyn)
      end

      def self.make(_client, _model : String) : self
        raise "Invalid method: Cannot make a TranscriptionModelHandle from a client + model identifier"
      end

      def transcription(request : Crig::TranscriptionRequest)
        @inner.transcription(request)
      end

      def transcription_request : Crig::TranscriptionRequestBuilder
        Crig::TranscriptionRequestBuilder.new(self)
      end
    end
  end
end
