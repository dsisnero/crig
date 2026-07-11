module Crig
    class ImageGenerationError < Exception
      enum Kind
        HttpError
        JsonError
        RequestError
        ResponseError
        ProviderError
        ProviderResponse
        Other
      end

      getter kind : Kind
      getter source_error : Exception?
      getter provider_response : ProviderResponseError?

      def initialize(message : String, @kind : Kind = Kind::Other, @source_error : Exception? = nil, @provider_response : ProviderResponseError? = nil)
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

      include Crig::ProviderResponseHelpers

      def provider_response_body : String?
        if @kind.provider_response?
          @provider_response.try(&.body)
        end
      end

      def provider_response_status : Int32?
        if @kind.provider_response?
          @provider_response.try(&.status)
        end
      end
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
