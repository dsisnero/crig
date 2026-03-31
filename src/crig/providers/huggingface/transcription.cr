module Crig
  module Providers
    module HuggingFace
      WHISPER_LARGE_V3       = "openai/whisper-large-v3"
      WHISPER_LARGE_V3_TURBO = "openai/whisper-large-v3-turbo"
      WHISPER_SMALL          = "openai/whisper-small"

      struct TranscriptionResponse
        include JSON::Serializable

        getter text : String

        def initialize(@text : String)
        end

        def to_crig_response : Crig::TranscriptionResponse(self)
          Crig::TranscriptionResponse(self).new(@text, self)
        end
      end

      struct TranscriptionModel
        include Crig::TranscriptionModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def transcription_request : Crig::TranscriptionRequestBuilder
          Crig::TranscriptionRequestBuilder.new(self)
        end

        def transcription(request : Crig::TranscriptionRequest)
          route = @client.subprovider.transcription_endpoint(@model)
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "inputs", Base64.strict_encode(request.data)
            end
          end

          response = @client.post_json(route, payload.to_json)
          body = response.body
          raise Crig::TranscriptionError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          envelope = ApiResponse(TranscriptionResponse).from_json_value(parsed) { |value| TranscriptionResponse.from_json(value.to_json) }
          if error = envelope.error
            raise Crig::TranscriptionError.new(error.to_json)
          end
          transcription_response = envelope.ok || raise Crig::TranscriptionError.new("HuggingFace response did not include a success payload")
          transcription_response.to_crig_response
        end
      end
    end
  end
end
