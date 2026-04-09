module Crig
  module Providers
    module XAI
      GROK_IMAGINE_IMAGE     = "grok-imagine-image"
      GROK_IMAGINE_IMAGE_PRO = "grok-imagine-image-pro"

      struct ImageGenerationData
        include JSON::Serializable

        @[JSON::Field(key: "b64_json")]
        getter b64_json : String

        def initialize(@b64_json : String)
        end
      end

      struct ImageGenerationResponse
        include JSON::Serializable

        getter data : Array(ImageGenerationData)

        def initialize(@data : Array(ImageGenerationData))
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
              json.field "response_format", "b64_json"
              json.field "aspect_ratio", "1:1"
            end
          end

          merged_payload = if additional_params = request.additional_params
                             JSON.parse(OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
                           else
                             payload
                           end

          response = @client.post_json("/v1/images/generations", merged_payload.to_json)
          unless response.status_code < 400
            raise Crig::ImageGenerationError.provider_error("#{response.status}: #{response.body}")
          end

          payload_text = response.body
          parsed = ApiResponse(ImageGenerationResponse).from_json_value(JSON.parse(payload_text)) do |value|
            ImageGenerationResponse.from_json(value.to_json)
          end
          if error = parsed.error
            raise Crig::ImageGenerationError.provider_error(error.message)
          end
          body = parsed.ok || raise Crig::ImageGenerationError.response_error("No image data returned")

          first = body.data.first?
          raise Crig::ImageGenerationError.response_error("No image data returned") unless first

          begin
            image = Base64.decode(first.b64_json)
            Crig::ImageGenerationResponse(ImageGenerationResponse).new(image, body)
          rescue ex
            raise Crig::ImageGenerationError.response_error("Base64 decode error: #{ex.message || ex.class.name}")
          end
        end
      end
    end
  end
end
