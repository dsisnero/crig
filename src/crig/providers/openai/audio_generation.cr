module Crig
  module Providers
    module OpenAI
      TTS_1    = "tts-1"
      TTS_1_HD = "tts-1-hd"

      struct AudioGenerationModel
        include Crig::AudioGenerationModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def audio_generation_request : Crig::AudioGenerationRequestBuilder
          Crig::AudioGenerationRequestBuilder.new(self)
        end

        def audio_generation(request : Crig::AudioGenerationRequest)
          payload = OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "input", request.text
              json.field "voice", request.voice
              json.field "speed", request.speed
            end
          end

          merged_payload = if additional_params = request.additional_params
                             JSON.parse(OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
                           else
                             payload
                           end

          response = @client.post_json("/audio/speech", merged_payload.to_json, {"Accept" => "application/octet-stream"})

          unless response.status_code < 400
            raise Crig::AudioGenerationError.new("#{response.status}: #{response.body}")
          end

          bytes = response.body.to_slice
          Crig::AudioGenerationResponse(Bytes).new(bytes, Bytes.new(bytes.size) { |i| bytes[i] })
        end
      end

      struct Client
        include Crig::AudioGenerationClient(Crig::Providers::OpenAI::AudioGenerationModel)

        def audio_generation_model(model : String) : Crig::Providers::OpenAI::AudioGenerationModel
          Crig::Providers::OpenAI::AudioGenerationModel.make(self, model)
        end
      end
    end
  end
end
