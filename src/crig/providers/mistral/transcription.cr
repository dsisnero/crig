module Crig
  module Providers
    module Mistral
      VOXTRAL_MINI  = "voxtral-mini-latest"
      VOXTRAL_SMALL = "voxtral-small-latest"

      struct TranscriptionUsage
        include JSON::Serializable

        @[JSON::Field(key: "prompt_audio_seconds")]
        getter prompt_audio_seconds : Int32?
        @[JSON::Field(key: "prompt_tokens")]
        getter prompt_tokens : Int32
        @[JSON::Field(key: "total_tokens")]
        getter total_tokens : Int32
        @[JSON::Field(key: "completion_tokens")]
        getter completion_tokens : Int32
        @[JSON::Field(key: "prompt_tokens_details")]
        getter prompt_tokens_details : JSON::Any?

        def initialize(
          @prompt_audio_seconds : Int32? = nil,
          @prompt_tokens : Int32 = 0,
          @total_tokens : Int32 = 0,
          @completion_tokens : Int32 = 0,
          @prompt_tokens_details : JSON::Any? = nil,
        )
        end
      end

      struct SegmentChunk
        include JSON::Serializable

        getter start : Float32
        getter end : Float32
        getter text : String
        getter score : Float32?
        getter speaker_id : String?
        @[JSON::Field(key: "type")]
        getter segment_type : String

        def initialize(
          @start : Float32,
          @end : Float32,
          @text : String,
          @score : Float32? = nil,
          @speaker_id : String? = nil,
          @segment_type : String = "transcription_segment",
        )
        end
      end

      struct MistralTranscriptionResponse
        include JSON::Serializable

        getter language : String?
        getter model : String
        getter segments : Array(SegmentChunk)
        getter text : String
        getter usage : TranscriptionUsage

        def initialize(
          @model : String,
          @segments : Array(SegmentChunk),
          @text : String,
          @usage : TranscriptionUsage,
          @language : String? = nil,
        )
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
          builder = HTTP::FormData::Builder.new(io)
          builder.field("model", @model)
          builder.file("file", IO::Memory.new(request.data), HTTP::FormData::FileMetadata.new(filename: request.filename))
          if language = request.language
            builder.field("language", language)
          end
          if temperature = request.temperature
            builder.field("temperature", temperature.to_s)
          end
          if params = request.additional_params
            hash = params.as_h? || raise Crig::TranscriptionError.new("Additional Parameters to Mistral Transcription should be a map")
            hash.each do |key, value|
              builder.field(key, value.raw.is_a?(String) ? value.as_s : value.to_json)
            end
          end
          builder.finish

          response = HTTP::Client.exec(
            "POST",
            @client.build_uri("/v1/audio/transcriptions"),
            headers: HTTP::Headers{
              "Authorization" => "Bearer #{@client.api_key.token}",
              "Content-Type"  => builder.content_type,
              "Accept"        => "application/json",
            },
            body: io.to_s,
          )
          body = response.body
          raise Crig::TranscriptionError.new(body) if response.status_code >= 400

          MistralTranscriptionResponse.from_json(body).to_crig_response
        end
      end
    end
  end
end
