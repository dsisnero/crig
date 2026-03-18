module Crig
  module Client
    module AudioGenerationClient(M)
      abstract def audio_generation_model(model : String) : M
    end

    module AudioGenerationClientDyn
      abstract def audio_generation_model(model : String) : Crig::AudioGenerationModelDyn
    end

    struct AudioGenerationModelHandle
      include Crig::AudioGenerationModel

      getter inner : Crig::AudioGenerationModelDyn

      def initialize(@inner : Crig::AudioGenerationModelDyn)
      end

      def audio_generation(request : Crig::AudioGenerationRequest)
        @inner.audio_generation(request)
      end

      def audio_generation_request : Crig::AudioGenerationRequestBuilder
        Crig::AudioGenerationRequestBuilder.new(self)
      end
    end
  end
end
