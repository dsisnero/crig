module Crig
  module Providers
    module HuggingFace
      Flux1            = "black-forest-labs/FLUX.1-dev"
      Kolors           = "Kwai-Kolors/Kolors"
      StableDiffusion3 = "stabilityai/stable-diffusion-3-medium-diffusers"

      struct ImageGenerationResponse
        getter data : Bytes

        def initialize(@data : Bytes)
        end

        def to_crig_response : Crig::ImageGenerationResponse(self)
          Crig::ImageGenerationResponse(self).new(@data, self)
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
          route = @client.subprovider.image_generation_endpoint(@model)
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "inputs", request.prompt
              json.field "parameters" do
                json.object do
                  json.field "width", request.width
                  json.field "height", request.height
                end
              end
            end
          end

          response = @client.post_json(route, payload.to_json, "application/octet-stream")
          body = response.body
          raise Crig::ImageGenerationError.new("#{response.status_code}: #{body}") if response.status_code >= 400

          ImageGenerationResponse.new(body.to_slice).to_crig_response
        end
      end
    end
  end
end
