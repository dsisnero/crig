require "http/client"

module Crig
  module Providers
    module OpenRouter
      GPT_4O_MINI_TTS  = "openai/gpt-4o-mini-tts-2025-12-15"
      VOXTRAL_MINI_TTS = "mistralai/voxtral-mini-tts-2603"
      KOKORO_82M       = "hexgrad/kokoro-82m"

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

        def audio_generation(text : String, voice : String) : Crig::AudioGenerationRequestBuilder
          audio_generation_request.text(text).voice(voice)
        end

        def audio_generation(request : Crig::AudioGenerationRequest)
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "input", request.text
              json.field "voice", request.voice
              json.field "response_format", "mp3"
              json.field "speed", request.speed
            end
          end

          merged_payload = if additional_params = request.additional_params
                             JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
                           else
                             payload
                           end

          response = @client.post_json("/audio/speech", merged_payload.to_json, {"Accept" => "application/octet-stream"})

          unless response.success?
            raise Crig::AudioGenerationError.provider_error("#{response.status_code}: #{response.body}")
          end

          bytes = response.body.to_slice
          Crig::AudioGenerationResponse(Bytes).new(bytes, Bytes.new(bytes.size) { |i| bytes[i] })
        end
      end

      struct Client
        include Crig::AudioGenerationClient(Crig::Providers::OpenRouter::AudioGenerationModel)

        def audio_generation_model(model : String) : Crig::Providers::OpenRouter::AudioGenerationModel
          Crig::Providers::OpenRouter::AudioGenerationModel.make(self, model)
        end
      end
    end
  end
end
