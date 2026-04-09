module Crig
  module Providers
    module XAI
      TTS_1 = "tts-1"

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
          voice = request.voice.empty? ? "eve" : request.voice
          payload = OpenAI.build_json_any do |json|
            json.object do
              json.field "text", request.text
              json.field "voice_id", voice
              json.field "language", "en"
            end
          end

          merged_payload = if additional_params = request.additional_params
                             JSON.parse(OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
                           else
                             payload
                           end

          response = @client.post_json("/v1/tts", merged_payload.to_json, {"Accept" => "application/octet-stream"})

          unless response.status_code < 400
            raise Crig::AudioGenerationError.provider_error("#{response.status}: #{response.body}")
          end

          bytes = response.body.to_slice
          Crig::AudioGenerationResponse(Bytes).new(bytes, Bytes.new(bytes.size) { |i| bytes[i] })
        end
      end
    end
  end
end
