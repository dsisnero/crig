module Crig
  class TranscriptionError < Exception
  end

  module Transcription
    abstract def transcription(filename : String, data : Bytes) : TranscriptionRequestBuilder
  end

  struct TranscriptionResponse(T)
    getter text : String
    getter response : T

    def initialize(@text : String, @response : T)
    end
  end

  module TranscriptionModel
    include Crig::WasmCompatSend
    include Crig::WasmCompatSync

    abstract def transcription(request : TranscriptionRequest)
    abstract def transcription_request : TranscriptionRequestBuilder

    def transcription_async(request : TranscriptionRequest)
      Crig::Concurrency.run do
        transcription(request)
      end
    end
  end

  module TranscriptionModelDyn
    abstract def transcription(request : TranscriptionRequest)
    abstract def transcription_request : TranscriptionRequestBuilder

    def transcription_async(request : TranscriptionRequest)
      Crig::Concurrency.run do
        transcription(request)
      end
    end
  end

  struct TranscriptionRequest
    getter data : Bytes
    getter filename : String
    getter language : String?
    getter prompt : String?
    getter temperature : Float64?
    getter additional_params : JSON::Any?

    def initialize(
      @data : Bytes,
      @filename : String,
      @language : String? = nil,
      @prompt : String? = nil,
      @temperature : Float64? = nil,
      @additional_params : JSON::Any? = nil,
    )
    end
  end

  struct TranscriptionRequestBuilder
    getter model : TranscriptionModel
    getter data_value : Bytes
    getter filename_value : String?
    getter language_value : String?
    getter prompt_value : String?
    getter temperature_value : Float64?
    getter additional_params_value : JSON::Any?

    def initialize(
      @model : TranscriptionModel,
      @data_value : Bytes = Bytes.empty,
      @filename_value : String? = nil,
      @language_value : String? = nil,
      @prompt_value : String? = nil,
      @temperature_value : Float64? = nil,
      @additional_params_value : JSON::Any? = nil,
    )
    end

    def filename(filename : String?) : self
      self.class.new(@model, @data_value, filename, @language_value, @prompt_value, @temperature_value, @additional_params_value)
    end

    def data(data : Bytes) : self
      self.class.new(@model, data, @filename_value, @language_value, @prompt_value, @temperature_value, @additional_params_value)
    end

    def language(language : String) : self
      self.class.new(@model, @data_value, @filename_value, language, @prompt_value, @temperature_value, @additional_params_value)
    end

    def prompt(prompt : String) : self
      self.class.new(@model, @data_value, @filename_value, @language_value, prompt, @temperature_value, @additional_params_value)
    end

    def temperature(temperature : Float64) : self
      self.class.new(@model, @data_value, @filename_value, @language_value, @prompt_value, temperature, @additional_params_value)
    end

    def additional_params(additional_params : JSON::Any) : self
      merged = @additional_params_value ? Crig::JSONUtils.merge(@additional_params_value.as(JSON::Any), additional_params) : additional_params
      self.class.new(@model, @data_value, @filename_value, @language_value, @prompt_value, @temperature_value, merged)
    end

    def additional_params_opt(additional_params : JSON::Any?) : self
      self.class.new(@model, @data_value, @filename_value, @language_value, @prompt_value, @temperature_value, additional_params)
    end

    def build : TranscriptionRequest
      raise TranscriptionError.new("Data cannot be empty!") if @data_value.empty?

      TranscriptionRequest.new(
        @data_value,
        @filename_value || "file",
        @language_value,
        @prompt_value,
        @temperature_value,
        @additional_params_value,
      )
    end

    def send
      @model.transcription(build)
    end

    def send_async
      @model.transcription_async(build)
    end
  end
end
