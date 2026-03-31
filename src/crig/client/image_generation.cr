module Crig
  module Client
    module ImageGenerationClient(M)
      abstract def image_generation_model(model : String) : M

      def custom_image_generation_model(model : String) : M
        image_generation_model(model)
      end
    end

    module ImageGenerationClientDyn
      abstract def image_generation_model(model : String) : Crig::ImageGenerationModelDyn
    end

    struct ImageGenerationModelHandle
      include Crig::ImageGenerationModel

      getter inner : Crig::ImageGenerationModelDyn

      def initialize(@inner : Crig::ImageGenerationModelDyn)
      end

      def self.make(_client, _model : String) : self
        raise "Invalid method: Cannot make an ImageGenerationModelHandle from a client + model identifier"
      end

      def image_generation(request : Crig::ImageGenerationRequest)
        @inner.image_generation(request)
      end

      def image_generation_request : Crig::ImageGenerationRequestBuilder
        Crig::ImageGenerationRequestBuilder.new(self)
      end
    end
  end
end
