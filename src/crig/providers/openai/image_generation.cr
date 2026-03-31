require "base64"

module Crig
  module Providers
    module OpenAI
      DALL_E_2    = "dall-e-2"
      DALL_E_3    = "dall-e-3"
      GPT_IMAGE_1 = "gpt-image-1"

      struct ImageGenerationData
        include JSON::Serializable

        @[JSON::Field(key: "b64_json")]
        getter b64_json : String

        def initialize(@b64_json : String)
        end
      end

      struct ImageGenerationResponse
        include JSON::Serializable

        getter created : Int32
        getter data : Array(ImageGenerationData)

        def initialize(@created : Int32, @data : Array(ImageGenerationData))
        end

        def to_crig_response : Crig::ImageGenerationResponse(self)
          image = Base64.decode(data.first.b64_json)
          Crig::ImageGenerationResponse(self).new(image, self)
        end
      end

      struct ImageGenerationModel
        include Crig::ImageGenerationModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def image_generation_request : Crig::ImageGenerationRequestBuilder
          Crig::ImageGenerationRequestBuilder.new(self)
        end

        def image_generation(request : Crig::ImageGenerationRequest)
          payload = OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "prompt", request.prompt
              json.field "size", "#{request.width}x#{request.height}"
              unless @model == GPT_IMAGE_1
                json.field "response_format", "b64_json"
              end
            end
          end

          merged_payload = if additional_params = request.additional_params
                             JSON.parse(OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
                           else
                             payload
                           end

          response = @client.post_json("/images/generations", merged_payload.to_json)
          text = response.body

          unless response.success?
            raise Crig::ImageGenerationError.new("#{response.status}: #{text}")
          end

          parsed = JSON.parse(text)
          if error = parsed["error"]?
            raise Crig::ImageGenerationError.new(error["message"].as_s)
          end

          ImageGenerationResponse.from_json(text).to_crig_response
        end
      end

      struct Client
        include Crig::ImageGenerationClient(Crig::Providers::OpenAI::ImageGenerationModel)

        def image_generation_model(model : String) : Crig::Providers::OpenAI::ImageGenerationModel
          Crig::Providers::OpenAI::ImageGenerationModel.make(self, model)
        end
      end
    end
  end
end
