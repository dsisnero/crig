require "http/formdata"

module Crig
  module Providers
    module OpenAI
      WHISPER_1 = "whisper-1"

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
          io = IO::Memory.new
          form = HTTP::FormData::Builder.new(io)
          form.field("model", @model)
          form.file("file", IO::Memory.new(request.data), HTTP::FormData::FileMetadata.new(filename: request.filename))
          if language = request.language
            form.field("language", language)
          end
          if prompt = request.prompt
            form.field("prompt", prompt)
          end
          if temperature = request.temperature
            form.field("temperature", temperature.to_s)
          end
          if additional_params = request.additional_params
            additional_params.as_h.each do |key, value|
              form.field(key, value.to_s)
            end
          end
          form.finish

          response = HTTP::Client.exec(
            "POST",
            "#{@client.base_url.rstrip('/')}/audio/transcriptions",
            headers: HTTP::Headers{
              "Authorization" => "Bearer #{@client.api_key.token}",
              "Content-Type"  => form.content_type,
              "Accept"        => "application/json",
            },
            body: io.to_s,
          )
          text = response.body

          if response.status_code >= 400
            raise Crig::TranscriptionError.new(text)
          end

          parsed = JSON.parse(text)
          if error = parsed["error"]?
            raise Crig::TranscriptionError.new(error["message"].as_s)
          end

          TranscriptionResponse.from_json(text).to_crig_response
        end
      end

      struct Client
        include Crig::TranscriptionClient(Crig::Providers::OpenAI::TranscriptionModel)

        def transcription_model(model : String) : Crig::Providers::OpenAI::TranscriptionModel
          Crig::Providers::OpenAI::TranscriptionModel.make(self, model)
        end
      end
    end
  end
end
