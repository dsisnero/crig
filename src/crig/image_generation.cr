module Crig
  class ImageGenerationError < Exception
  end

  module ImageGeneration
    abstract def image_generation(prompt : String, size : {Int32, Int32}) : ImageGenerationRequestBuilder
  end

  struct ImageGenerationResponse(T)
    getter image : Bytes
    getter response : T

    def initialize(@image : Bytes, @response : T)
    end
  end

  module ImageGenerationModel
    abstract def image_generation(request : ImageGenerationRequest)
    abstract def image_generation_request : ImageGenerationRequestBuilder

    def image_generation_async(request : ImageGenerationRequest)
      Crig::Concurrency.run do
        image_generation(request)
      end
    end
  end

  module ImageGenerationModelDyn
    abstract def image_generation(request : ImageGenerationRequest)
    abstract def image_generation_request : ImageGenerationRequestBuilder

    def image_generation_async(request : ImageGenerationRequest)
      Crig::Concurrency.run do
        image_generation(request)
      end
    end
  end

  struct ImageGenerationRequest
    getter prompt : String
    getter width : Int32
    getter height : Int32
    getter additional_params : JSON::Any?

    def initialize(@prompt : String, @width : Int32, @height : Int32, @additional_params : JSON::Any? = nil)
    end
  end

  struct ImageGenerationRequestBuilder
    getter model : ImageGenerationModel
    getter prompt_value : String
    getter width_value : Int32
    getter height_value : Int32
    getter additional_params_value : JSON::Any?

    def initialize(
      @model : ImageGenerationModel,
      @prompt_value : String = "",
      @width_value : Int32 = 256,
      @height_value : Int32 = 256,
      @additional_params_value : JSON::Any? = nil,
    )
    end

    def prompt(prompt : String) : self
      self.class.new(@model, prompt, @width_value, @height_value, @additional_params_value)
    end

    def width(width : Int32) : self
      self.class.new(@model, @prompt_value, width, @height_value, @additional_params_value)
    end

    def height(height : Int32) : self
      self.class.new(@model, @prompt_value, @width_value, height, @additional_params_value)
    end

    def additional_params(params : JSON::Any) : self
      self.class.new(@model, @prompt_value, @width_value, @height_value, params)
    end

    def build : ImageGenerationRequest
      ImageGenerationRequest.new(@prompt_value, @width_value, @height_value, @additional_params_value)
    end

    def send
      @model.image_generation(build)
    end

    def send_async
      @model.image_generation_async(build)
    end
  end
end
