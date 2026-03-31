require "base64"

module Crig
  module Providers
    module Gemini
      TRANSCRIPTION_PREAMBLE = "Translate the provided audio exactly. Do not add additional information."

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
          generation_config = build_generation_config(request.additional_params, request.temperature)
          mime_type = mime_type_for(request.filename)
          body = GenerateContentRequest.new(
            contents: [
              Content.new(
                [
                  Part.new(
                    PartKind.inline_data(
                      Blob.new(mime_type, Base64.strict_encode(request.data))
                    ),
                    thought: false,
                  ),
                ],
                role: Role::User,
              ),
            ],
            generation_config: generation_config,
            system_instruction: Content.new([Part.text(TRANSCRIPTION_PREAMBLE)], role: Role::Model),
          )

          response = @client.post_json("/v1beta/models/#{@model}:generateContent", body.to_json)
          raise Crig::TranscriptionError.new(response.body) if response.status_code >= 400

          parsed = GenerateContentResponse.from_json(response.body)
          Crig::TranscriptionResponse(GenerateContentResponse).new(extract_text(parsed), parsed)
        end

        private def build_generation_config(additional_params : JSON::Any?, temperature : Float64?) : GenerationConfig?
          config = additional_params ? GenerationConfig.from_json(additional_params.to_json) : GenerationConfig.new
          config = GenerationConfig.new(
            temperature: temperature || config.temperature,
            max_output_tokens: config.max_output_tokens,
            response_mime_type: config.response_mime_type,
            response_json_schema: config.response_json_schema,
            thinking_config: config.thinking_config,
            image_config: config.image_config,
          )
          config.empty? ? nil : config
        end

        private def extract_text(response : GenerateContentResponse) : String
          candidate = response.candidates.first? || raise Crig::TranscriptionError.new("No response candidates in response")
          content = candidate.content || raise Crig::TranscriptionError.new("Response content contains no text")
          part = content.parts.first? || raise Crig::TranscriptionError.new("Response content contains no text")
          text = part.part.text
          raise Crig::TranscriptionError.new("Response content was not text") unless text
          text
        end

        private def mime_type_for(filename : String) : String
          case File.extname(filename).downcase
          when ".wav"  then "audio/wav"
          when ".mp3"  then "audio/mpeg"
          when ".m4a"  then "audio/mp4"
          when ".mp4"  then "audio/mp4"
          when ".flac" then "audio/flac"
          when ".aac"  then "audio/aac"
          when ".ogg"  then "audio/ogg"
          else
            "audio/mpeg"
          end
        end
      end

      struct Client
        include Crig::TranscriptionClient(Crig::Providers::Gemini::TranscriptionModel)

        def transcription_model(model : String) : Crig::Providers::Gemini::TranscriptionModel
          Crig::Providers::Gemini::TranscriptionModel.make(self, model)
        end
      end
    end
  end
end
