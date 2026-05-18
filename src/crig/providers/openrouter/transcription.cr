require "http/client"
require "base64"

module Crig
  module Providers
    module OpenRouter
      WHISPER_1              = "openai/whisper-1"
      WHISPER_LARGE_V3_TURBO = "openai/whisper-large-v3-turbo"
      WHISPER_LARGE_V3       = "openai/whisper-large-v3"
      GPT_4O_TRANSCRIBE      = "openai/gpt-4o-transcribe"
      GPT_4O_MINI_TRANSCRIBE = "openai/gpt-4o-mini-transcribe"
      CHIRP_3                = "google/chirp-3"

      struct TranscriptionResponse
        include JSON::Serializable

        getter text : String

        def initialize(@text : String)
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

        def transcription(filename : String, data : Bytes) : Crig::TranscriptionRequestBuilder
          transcription_request.filename(filename).data(data)
        end

        def transcription(request : Crig::TranscriptionRequest)
          base64_data = Base64.strict_encode(request.data)

          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field("input_audio") do
                json.object do
                  json.field "data", base64_data
                  json.field "format", request.filename ? infer_format(request.filename) : "wav"
                end
              end
              json.field "language", request.language unless request.language.nil?
              json.field "temperature", request.temperature unless request.temperature.nil?
            end
          end

          merged_payload = if additional_params = request.additional_params
                             JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
                           else
                             payload
                           end

          headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
          response = @client.post_json("/audio/transcriptions", merged_payload.to_json, headers)

          unless response.success?
            raise Crig::TranscriptionError.provider_error("#{response.status_code}: #{response.body}")
          end

          parsed = JSON.parse(response.body)
          text = parsed["text"].as_s

          Crig::TranscriptionResponse(TranscriptionResponse).new(
            text,
            TranscriptionResponse.new(text),
          )
        end

        private def infer_format(filename : String) : String
          ext = File.extname(filename).downcase.lstrip('.')
          case ext
          when "mp3"  then "mp3"
          when "wav"  then "wav"
          when "ogg"  then "ogg"
          when "flac" then "flac"
          when "m4a"  then "m4a"
          when "webm" then "webm"
          when "mpga" then "mp3"
          when "mpeg" then "mp3"
          else             "wav"
          end
        end
      end

      struct Client
        include Crig::TranscriptionClient(Crig::Providers::OpenRouter::TranscriptionModel)

        def transcription_model(model : String) : Crig::Providers::OpenRouter::TranscriptionModel
          Crig::Providers::OpenRouter::TranscriptionModel.make(self, model)
        end
      end
    end
  end
end
