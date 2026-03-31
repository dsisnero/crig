module Crig
  class AudioGenerationError < Exception
    enum Kind
      HttpError
      JsonError
      RequestError
      ResponseError
      ProviderError
      Other
    end

    getter kind : Kind
    getter source_error : Exception?

    def initialize(message : String, @kind : Kind = Kind::Other, @source_error : Exception? = nil)
      super(message)
    end

    def self.http_error(error : Exception) : self
      new("HttpError: #{error.message || error.class.name}", Kind::HttpError, error)
    end

    def self.json_error(error : Exception) : self
      new("JsonError: #{error.message || error.class.name}", Kind::JsonError, error)
    end

    def self.request_error(error : Exception) : self
      new("RequestError: #{error.message || error.class.name}", Kind::RequestError, error)
    end

    def self.response_error(message : String) : self
      new("ResponseError: #{message}", Kind::ResponseError)
    end

    def self.provider_error(message : String) : self
      new("ProviderError: #{message}", Kind::ProviderError)
    end
  end

  module AudioGeneration
    abstract def audio_generation(text : String, voice : String) : AudioGenerationRequestBuilder
  end

  struct AudioGenerationResponse(T)
    getter audio : Bytes
    getter response : T

    def initialize(@audio : Bytes, @response : T)
    end
  end

  module AudioGenerationModel
    include Crig::WasmCompatSend
    include Crig::WasmCompatSync

    abstract def audio_generation(request : AudioGenerationRequest)
    abstract def audio_generation_request : AudioGenerationRequestBuilder

    def audio_generation_async(request : AudioGenerationRequest)
      Crig::Concurrency.run do
        audio_generation(request)
      end
    end
  end

  module AudioGenerationModelDyn
    abstract def audio_generation(request : AudioGenerationRequest)
    abstract def audio_generation_request : AudioGenerationRequestBuilder

    def audio_generation_async(request : AudioGenerationRequest)
      Crig::Concurrency.run do
        audio_generation(request)
      end
    end
  end

  struct AudioGenerationRequest
    getter text : String
    getter voice : String
    getter speed : Float32
    getter additional_params : JSON::Any?

    def initialize(@text : String, @voice : String, @speed : Float32, @additional_params : JSON::Any? = nil)
    end
  end

  struct AudioGenerationRequestBuilder
    getter model : AudioGenerationModel
    getter text_value : String
    getter voice_value : String
    getter speed_value : Float32
    getter additional_params_value : JSON::Any?

    def initialize(
      @model : AudioGenerationModel,
      @text_value : String = "",
      @voice_value : String = "",
      @speed_value : Float32 = 1.0_f32,
      @additional_params_value : JSON::Any? = nil,
    )
    end

    def text(text : String) : self
      self.class.new(@model, text, @voice_value, @speed_value, @additional_params_value)
    end

    def voice(voice : String) : self
      self.class.new(@model, @text_value, voice, @speed_value, @additional_params_value)
    end

    def speed(speed : Float32) : self
      self.class.new(@model, @text_value, @voice_value, speed, @additional_params_value)
    end

    def additional_params(params : JSON::Any) : self
      self.class.new(@model, @text_value, @voice_value, @speed_value, params)
    end

    def build : AudioGenerationRequest
      AudioGenerationRequest.new(@text_value, @voice_value, @speed_value, @additional_params_value)
    end

    def send
      @model.audio_generation(build)
    end

    def send_async
      @model.audio_generation_async(build)
    end
  end
end
