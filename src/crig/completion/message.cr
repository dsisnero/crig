module Crig
  module Completion
    class MessageError < Exception
    end

    module ConvertMessage
      abstract def convert_from_message(message : Message)
    end

    struct Text
      include JSON::Serializable

      getter text : String

      def initialize(@text : String)
      end

      def self.from(text : String) : self
        new(text)
      end
    end

    struct ToolFunction
      include JSON::Serializable

      getter name : String
      getter arguments : JSON::Any

      def initialize(@name : String, @arguments : JSON::Any)
      end
    end

    struct ToolCall
      property call_id : String?
      property signature : String?
      property additional_params : JSON::Any?
      getter id : String
      getter function : ToolFunction

      def initialize(
        @id : String,
        @function : ToolFunction,
        @call_id : String? = nil,
        @signature : String? = nil,
        @additional_params : JSON::Any? = nil,
      )
      end

      def with_call_id(call_id : String) : self
        self.class.new(@id, @function, call_id, @signature, @additional_params)
      end

      def with_signature(signature : String?) : self
        self.class.new(@id, @function, @call_id, signature, @additional_params)
      end

      def with_additional_params(additional_params : JSON::Any?) : self
        self.class.new(@id, @function, @call_id, @signature, additional_params)
      end
    end

    struct ReasoningContent
      enum Kind
        Text
        Encrypted
        Redacted
        Summary
      end

      getter kind : Kind
      getter text : String?
      getter signature : String?
      getter data : String?
      getter summary : String?

      def initialize(
        @kind : Kind,
        @text : String? = nil,
        @signature : String? = nil,
        @data : String? = nil,
        @summary : String? = nil,
      )
      end

      def self.text(text : String, signature : String? = nil) : self
        new(Kind::Text, text: text, signature: signature)
      end

      def self.encrypted(data : String) : self
        new(Kind::Encrypted, data: data)
      end

      def self.redacted(data : String) : self
        new(Kind::Redacted, data: data)
      end

      def self.summary(text : String) : self
        new(Kind::Summary, summary: text)
      end

      def to_json(json : JSON::Builder) : Nil
        json.object do
          case @kind
          in .text?
            json.field "type", "text"
            json.field "content" do
              json.object do
                json.field "text", @text
                if signature = @signature
                  json.field "signature", signature
                end
              end
            end
          in .encrypted?
            json.field "type", "encrypted"
            json.field "content", @data
          in .redacted?
            json.field "type", "redacted"
            json.field "content" do
              json.object do
                json.field "data", @data
              end
            end
          in .summary?
            json.field "type", "summary"
            json.field "content", @summary
          end
        end
      end

      # ameba:disable Metrics/CyclomaticComplexity
      def self.new(pull : JSON::PullParser)
        type = nil
        text = nil
        signature = nil
        data = nil
        summary = nil

        pull.read_begin_object
        until pull.kind.end_object?
          key = pull.read_object_key
          case key
          when "type"
            type = pull.read_string
          when "content"
            case type
            when "text"
              pull.read_begin_object
              until pull.kind.end_object?
                nested_key = pull.read_object_key
                case nested_key
                when "text"
                  text = pull.read_string
                when "signature"
                  signature = pull.read_string
                else
                  pull.skip
                end
              end
              pull.read_end_object
            when "redacted"
              pull.read_begin_object
              until pull.kind.end_object?
                nested_key = pull.read_object_key
                if nested_key == "data"
                  data = pull.read_string
                else
                  pull.skip
                end
              end
              pull.read_end_object
            when "encrypted"
              data = pull.read_string
            when "summary"
              summary = pull.read_string
            else
              pull.skip
            end
          else
            pull.skip
          end
        end
        pull.read_end_object

        case type
        when "text"      then text(text || "", signature)
        when "encrypted" then encrypted(data || "")
        when "redacted"  then redacted(data || "")
        when "summary"   then summary(summary || "")
        else
          raise MessageError.new("Unknown reasoning content type: #{type}")
        end
      end
      # ameba:enable Metrics/CyclomaticComplexity
    end

    struct Reasoning
      getter id : String?
      getter content : Array(ReasoningContent)

      def initialize(@content : Array(ReasoningContent), @id : String? = nil)
      end

      def self.new(input : String) : self
        new_with_signature(input, nil)
      end

      def self.new_with_signature(input : String, signature : String?) : self
        new([ReasoningContent.text(input, signature)])
      end

      def optional_id(id : String?) : self
        self.class.new(@content, id)
      end

      def with_id(id : String) : self
        optional_id(id)
      end

      def with_signature(signature : String?) : self
        updated = @content.map do |item|
          if item.kind.text?
            text = item.text || ""
            ReasoningContent.text(text, signature)
          else
            item
          end
        end
        self.class.new(updated, @id)
      end

      def self.multi(input : Array(String)) : self
        new(input.map { |text| ReasoningContent.text(text) })
      end

      def self.redacted(data : String) : self
        new([ReasoningContent.redacted(data)])
      end

      def self.encrypted(data : String) : self
        new([ReasoningContent.encrypted(data)])
      end

      def self.summaries(input : Array(String)) : self
        new(input.map { |text| ReasoningContent.summary(text) })
      end

      def display_text : String
        @content.compact_map do |item|
          case item.kind
          in .text?
            item.text
          in .summary?
            item.summary
          in .redacted?
            item.data
          in .encrypted?
            nil
          end
        end.join('\n')
      end

      def first_text : String?
        item = @content.find(&.kind.text?)
        item ? item.text : nil
      end

      def first_signature : String?
        item = @content.find(&.kind.text?)
        item ? item.signature : nil
      end

      def encrypted_content : String?
        item = @content.find(&.kind.encrypted?)
        item ? item.data : nil
      end
    end

    struct DocumentSourceKind
      enum Kind
        Url
        Base64
        Raw
        String
        Unknown
      end

      getter kind : Kind
      getter string_value : String?
      getter bytes_value : Bytes?

      def initialize(@kind : Kind, @string_value : String? = nil, @bytes_value : Bytes? = nil)
      end

      def self.url(url : String) : self
        new(Kind::Url, string_value: url)
      end

      def self.base64(value : String) : self
        new(Kind::Base64, string_value: value)
      end

      def self.raw(bytes : Bytes) : self
        new(Kind::Raw, bytes_value: bytes)
      end

      def self.string(input : String) : self
        new(Kind::String, string_value: input)
      end

      def self.unknown : self
        new(Kind::Unknown)
      end

      def try_into_inner : String?
        if @kind.url? || @kind.base64? || @kind.string?
          @string_value
        end
      end

      def to_s(io : IO) : Nil
        case @kind
        in .url?, .base64?, .string?
          io << @string_value
        in .raw?
          io << "<binary data>"
        in .unknown?
          io << "<unknown>"
        end
      end

      def to_json(json : JSON::Builder) : Nil
        json.object do
          case @kind
          in .url?
            json.field "type", "url"
            json.field "value", @string_value
          in .base64?
            json.field "type", "base64"
            json.field "value", @string_value
          in .raw?
            json.field "type", "raw"
            json.field "value", @bytes_value.try(&.to_a)
          in .string?
            json.field "type", "string"
            json.field "value", @string_value
          in .unknown?
            json.field "type", "unknown"
          end
        end
      end

      # ameba:disable Metrics/CyclomaticComplexity
      def self.new(pull : JSON::PullParser)
        type = nil
        string_value = nil
        bytes_value = nil

        pull.read_begin_object
        until pull.kind.end_object?
          key = pull.read_object_key
          case key
          when "type"
            type = pull.read_string
          when "value"
            case type
            when "raw"
              values = [] of UInt8
              pull.read_begin_array
              until pull.kind.end_array?
                values << pull.read_int.to_u8
              end
              pull.read_end_array
              bytes_value = Bytes.new(values.size) { |index| values[index] }
            else
              string_value = pull.read_string
            end
          else
            pull.skip
          end
        end
        pull.read_end_object

        case type
        when "url"    then url(string_value || "")
        when "base64" then base64(string_value || "")
        when "raw"    then raw(bytes_value || Bytes.empty)
        when "string" then string(string_value || "")
        else
          unknown
        end
      end
      # ameba:enable Metrics/CyclomaticComplexity
    end

    enum ImageMediaType
      JPEG
      PNG
      GIF
      WEBP
      HEIC
      HEIF
      SVG
    end

    enum DocumentMediaType
      PDF
      TXT
      RTF
      HTML
      CSS
      MARKDOWN
      CSV
      XML
      Javascript
      Python

      def code? : Bool
        javascript? || python?
      end

      # ameba:disable Naming/PredicateName
      def is_code : Bool
        code?
      end
      # ameba:enable Naming/PredicateName
    end

    enum AudioMediaType
      WAV
      MP3
      AIFF
      AAC
      OGG
      FLAC
      M4A
      PCM16
      PCM24
    end

    enum VideoMediaType
      AVI
      MP4
      MPEG
      MOV
      WEBM
    end

    enum ContentFormat
      Base64
      String
      Url
    end

    struct MediaType
      enum Kind
        Image
        Audio
        Document
        Video
      end

      getter kind : Kind
      getter image : ImageMediaType?
      getter audio : AudioMediaType?
      getter document : DocumentMediaType?
      getter video : VideoMediaType?

      def initialize(@kind : Kind, @image : ImageMediaType? = nil, @audio : AudioMediaType? = nil, @document : DocumentMediaType? = nil, @video : VideoMediaType? = nil)
      end

      def self.image(media_type : ImageMediaType) : self
        new(Kind::Image, image: media_type)
      end

      def self.audio(media_type : AudioMediaType) : self
        new(Kind::Audio, audio: media_type)
      end

      def self.document(media_type : DocumentMediaType) : self
        new(Kind::Document, document: media_type)
      end

      def self.video(media_type : VideoMediaType) : self
        new(Kind::Video, video: media_type)
      end

      def to_json(json : JSON::Builder) : Nil
        json.object do
          case @kind
          in .image?
            json.field "kind", "image"
            json.field "value", @image.to_s.downcase
          in .audio?
            json.field "kind", "audio"
            json.field "value", @audio.to_s.downcase
          in .document?
            json.field "kind", "document"
            json.field "value", @document.to_s
          in .video?
            json.field "kind", "video"
            json.field "value", @video.to_s.downcase
          end
        end
      end

      def self.new(pull : JSON::PullParser)
        kind = nil
        value = nil

        pull.read_begin_object
        until pull.kind.end_object?
          key = pull.read_object_key
          case key
          when "kind"
            kind = pull.read_string
          when "value"
            value = pull.read_string
          else
            pull.skip
          end
        end
        pull.read_end_object

        case kind
        when "image"
          image(MimeType.image_from_mime_type("image/#{value}").as(ImageMediaType))
        when "audio"
          audio(MimeType.audio_from_mime_type("audio/#{value}").as(AudioMediaType))
        when "document"
          document(DocumentMediaType.parse(value.as(String)))
        when "video"
          video(MimeType.video_from_mime_type("video/#{value}").as(VideoMediaType))
        else
          raise MessageError.new("Unknown media type kind: #{kind}")
        end
      end
      # ameba:enable Metrics/CyclomaticComplexity
    end

    enum ImageDetail
      Low
      High
      Auto

      def self.parse?(value : String) : self?
        return Low if value.downcase == "low"
        return High if value.downcase == "high"
        return Auto if value.downcase == "auto"
      end
    end

    module MimeType
      def self.from_mime_type(mime_type : String) : MediaType?
        image_from_mime_type(mime_type).try { |type| MediaType.image(type) } ||
          document_from_mime_type(mime_type).try { |type| MediaType.document(type) } ||
          audio_from_mime_type(mime_type).try { |type| MediaType.audio(type) } ||
          video_from_mime_type(mime_type).try { |type| MediaType.video(type) }
      end

      def self.to_mime_type(media_type : MediaType) : String
        case media_type.kind
        in .image?
          image_to_mime_type(media_type.image.as(ImageMediaType))
        in .audio?
          audio_to_mime_type(media_type.audio.as(AudioMediaType))
        in .document?
          document_to_mime_type(media_type.document.as(DocumentMediaType))
        in .video?
          video_to_mime_type(media_type.video.as(VideoMediaType))
        end
      end

      def self.image_from_mime_type(mime_type : String) : ImageMediaType?
        case mime_type
        when "image/jpeg"    then ImageMediaType::JPEG
        when "image/png"     then ImageMediaType::PNG
        when "image/gif"     then ImageMediaType::GIF
        when "image/webp"    then ImageMediaType::WEBP
        when "image/heic"    then ImageMediaType::HEIC
        when "image/heif"    then ImageMediaType::HEIF
        when "image/svg+xml" then ImageMediaType::SVG
        end
      end

      def self.image_to_mime_type(media_type : ImageMediaType) : String
        case media_type
        in .jpeg? then "image/jpeg"
        in .png?  then "image/png"
        in .gif?  then "image/gif"
        in .webp? then "image/webp"
        in .heic? then "image/heic"
        in .heif? then "image/heif"
        in .svg?  then "image/svg+xml"
        end
      end

      def self.document_from_mime_type(mime_type : String) : DocumentMediaType?
        case mime_type
        when "application/pdf"                               then DocumentMediaType::PDF
        when "text/plain"                                    then DocumentMediaType::TXT
        when "text/rtf"                                      then DocumentMediaType::RTF
        when "text/html"                                     then DocumentMediaType::HTML
        when "text/css"                                      then DocumentMediaType::CSS
        when "text/md", "text/markdown"                      then DocumentMediaType::MARKDOWN
        when "text/csv"                                      then DocumentMediaType::CSV
        when "text/xml"                                      then DocumentMediaType::XML
        when "application/x-javascript", "text/x-javascript" then DocumentMediaType::Javascript
        when "application/x-python", "text/x-python"         then DocumentMediaType::Python
        end
      end

      def self.document_to_mime_type(media_type : DocumentMediaType) : String
        case media_type
        in .pdf?        then "application/pdf"
        in .txt?        then "text/plain"
        in .rtf?        then "text/rtf"
        in .html?       then "text/html"
        in .css?        then "text/css"
        in .markdown?   then "text/markdown"
        in .csv?        then "text/csv"
        in .xml?        then "text/xml"
        in .javascript? then "application/x-javascript"
        in .python?     then "application/x-python"
        end
      end

      def self.audio_from_mime_type(mime_type : String) : AudioMediaType?
        case mime_type
        when "audio/wav"   then AudioMediaType::WAV
        when "audio/mp3"   then AudioMediaType::MP3
        when "audio/aiff"  then AudioMediaType::AIFF
        when "audio/aac"   then AudioMediaType::AAC
        when "audio/ogg"   then AudioMediaType::OGG
        when "audio/flac"  then AudioMediaType::FLAC
        when "audio/m4a"   then AudioMediaType::M4A
        when "audio/pcm16" then AudioMediaType::PCM16
        when "audio/pcm24" then AudioMediaType::PCM24
        end
      end

      def self.audio_to_mime_type(media_type : AudioMediaType) : String
        case media_type
        in .wav?   then "audio/wav"
        in .mp3?   then "audio/mp3"
        in .aiff?  then "audio/aiff"
        in .aac?   then "audio/aac"
        in .ogg?   then "audio/ogg"
        in .flac?  then "audio/flac"
        in .m4_a?  then "audio/m4a"
        in .pcm16? then "audio/pcm16"
        in .pcm24? then "audio/pcm24"
        end
      end

      def self.video_from_mime_type(mime_type : String) : VideoMediaType?
        case mime_type
        when "video/avi"  then VideoMediaType::AVI
        when "video/mp4"  then VideoMediaType::MP4
        when "video/mpeg" then VideoMediaType::MPEG
        when "video/mov"  then VideoMediaType::MOV
        when "video/webm" then VideoMediaType::WEBM
        end
      end

      def self.video_to_mime_type(media_type : VideoMediaType) : String
        case media_type
        in .avi?  then "video/avi"
        in .mp4?  then "video/mp4"
        in .mpeg? then "video/mpeg"
        in .mov?  then "video/mov"
        in .webm? then "video/webm"
        end
      end
    end

    struct Image
      getter data : DocumentSourceKind
      getter media_type : ImageMediaType?
      getter detail : ImageDetail?
      getter additional_params : JSON::Any?

      def initialize(
        @data : DocumentSourceKind,
        @media_type : ImageMediaType? = nil,
        @detail : ImageDetail? = nil,
        @additional_params : JSON::Any? = nil,
      )
      end

      def try_into_url : String
        case @data.kind
        in .url?
          @data.string_value || raise MessageError.new("URL image content is missing a string value")
        in .base64?
          media_type = @media_type || raise MessageError.new("A media type is required to create a valid base64-encoded image URL")
          "data:#{MimeType.image_to_mime_type(media_type)};base64,#{@data.string_value}"
        in .raw?, .string?, .unknown?
          raise MessageError.new("Tried to convert unknown type to a URL: #{@data}")
        end
      end

      def self.url(url : String, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.url(url), media_type, detail, additional_params)
      end

      def self.base64(data : String, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.base64(data), media_type, detail, additional_params)
      end

      def self.raw(data : Bytes, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.raw(data), media_type, detail, additional_params)
      end

      def self.string(data : String, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.string(data), media_type, detail, additional_params)
      end
    end

    struct Audio
      getter data : DocumentSourceKind
      getter media_type : AudioMediaType?
      getter additional_params : JSON::Any?

      def initialize(@data : DocumentSourceKind, @media_type : AudioMediaType? = nil, @additional_params : JSON::Any? = nil)
      end

      def self.url(url : String, media_type : AudioMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.url(url), media_type, additional_params)
      end

      def self.base64(data : String, media_type : AudioMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.base64(data), media_type, additional_params)
      end

      def self.raw(data : Bytes, media_type : AudioMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.raw(data), media_type, additional_params)
      end

      def self.string(data : String, media_type : AudioMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.string(data), media_type, additional_params)
      end
    end

    struct Video
      getter data : DocumentSourceKind
      getter media_type : VideoMediaType?
      getter additional_params : JSON::Any?

      def initialize(@data : DocumentSourceKind, @media_type : VideoMediaType? = nil, @additional_params : JSON::Any? = nil)
      end

      def self.url(url : String, media_type : VideoMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.url(url), media_type, additional_params)
      end

      def self.base64(data : String, media_type : VideoMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.base64(data), media_type, additional_params)
      end

      def self.raw(data : Bytes, media_type : VideoMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.raw(data), media_type, additional_params)
      end

      def self.string(data : String, media_type : VideoMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.string(data), media_type, additional_params)
      end
    end

    struct Document
      getter data : DocumentSourceKind
      getter media_type : DocumentMediaType?
      getter additional_params : JSON::Any?

      def initialize(@data : DocumentSourceKind, @media_type : DocumentMediaType? = nil, @additional_params : JSON::Any? = nil)
      end

      def self.url(url : String, media_type : DocumentMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.url(url), media_type, additional_params)
      end

      def self.base64(data : String, media_type : DocumentMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.base64(data), media_type, additional_params)
      end

      def self.raw(data : Bytes, media_type : DocumentMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.raw(data), media_type, additional_params)
      end

      def self.string(data : String, media_type : DocumentMediaType? = nil, additional_params : JSON::Any? = nil) : self
        new(DocumentSourceKind.string(data), media_type, additional_params)
      end
    end

    struct ToolResultContent
      struct ParsedImagePayload
        include JSON::Serializable

        getter type : String
        getter data : String
        @[JSON::Field(key: "mimeType")]
        getter mime_type : String
      end

      struct ParsedHybridPart
        include JSON::Serializable

        getter type : String
        getter data : String?
        @[JSON::Field(key: "mimeType")]
        getter mime_type : String?
      end

      struct ParsedHybridPayload
        include JSON::Serializable

        getter response : JSON::Any?
        getter parts : Array(ParsedHybridPart)?
      end

      enum Kind
        Text
        Image
      end

      getter kind : Kind
      getter text : Text?
      getter image : Image?

      def initialize(@kind : Kind, @text : Text? = nil, @image : Image? = nil)
      end

      def self.text(text : String) : self
        new(Kind::Text, text: Text.new(text))
      end

      def self.image_base64(data : String, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil) : self
        new(Kind::Image, image: Image.new(DocumentSourceKind.base64(data), media_type, detail))
      end

      def self.image_raw(data : Bytes, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil) : self
        new(Kind::Image, image: Image.new(DocumentSourceKind.raw(data), media_type, detail))
      end

      def self.image_url(url : String, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil) : self
        new(Kind::Image, image: Image.new(DocumentSourceKind.url(url), media_type, detail))
      end

      private def self.classify_tool_output(output : String) : Symbol
        parser = JSON::PullParser.new(output)
        has_parts = false
        has_response = false
        type = nil

        parser.read_begin_object
        until parser.kind.end_object?
          key = parser.read_object_key
          case key
          when "type"
            type = parser.read_string
          when "response"
            has_response = true
            parser.skip
          when "parts"
            has_parts = true
            parser.skip
          else
            parser.skip
          end
        end
        parser.read_end_object

        return :hybrid if has_parts || has_response
        return :image if type == "image"

        :text
      rescue JSON::ParseException
        :text
      end

      private def self.content_from_image_payload(data : String, mime_type : String) : self
        media_type = MimeType.image_from_mime_type(mime_type)
        if data.starts_with?("http://") || data.starts_with?("https://")
          image_url(data, media_type)
        else
          image_base64(data, media_type)
        end
      end

      def self.from_tool_output(output : String) : Crig::OneOrMany(self)
        case classify_tool_output(output)
        when :hybrid
          payload = ParsedHybridPayload.from_json(output)
          results = [] of self
          if response = payload.response
            results << text(response.to_json)
          end
          if parts = payload.parts
            parts.each do |part|
              next unless part.type == "image"
              data = part.data
              mime_type = part.mime_type
              next unless data && mime_type
              results << content_from_image_payload(data, mime_type)
            end
          end
          return Crig::OneOrMany(self).many(results) unless results.empty?
        when :image
          payload = ParsedImagePayload.from_json(output)
          return Crig::OneOrMany(self).one(content_from_image_payload(payload.data, payload.mime_type))
        end

        Crig::OneOrMany(self).one(text(output))
      end
    end

    struct ToolResult
      getter id : String
      getter call_id : String?
      getter content : Crig::OneOrMany(ToolResultContent)

      def initialize(@id : String, @content : Crig::OneOrMany(ToolResultContent), @call_id : String? = nil)
      end
    end

    struct UserContent
      enum Kind
        Text
        ToolResult
        Image
        Audio
        Video
        Document
      end

      getter kind : Kind
      getter text : Text?
      getter tool_result : ToolResult?
      getter image : Image?
      getter audio : Audio?
      getter video : Video?
      getter document : Document?

      def initialize(
        @kind : Kind,
        @text : Text? = nil,
        @tool_result : ToolResult? = nil,
        @image : Image? = nil,
        @audio : Audio? = nil,
        @video : Video? = nil,
        @document : Document? = nil,
      )
      end

      def self.text(text : String) : self
        new(Kind::Text, text: Text.new(text))
      end

      def self.tool_result(id : String, content : Crig::OneOrMany(ToolResultContent)) : self
        new(Kind::ToolResult, tool_result: ToolResult.new(id, content))
      end

      def self.tool_result_with_call_id(id : String, call_id : String, content : Crig::OneOrMany(ToolResultContent)) : self
        new(Kind::ToolResult, tool_result: ToolResult.new(id, content, call_id))
      end

      def self.image_base64(data : String, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil) : self
        new(Kind::Image, image: Image.new(DocumentSourceKind.base64(data), media_type, detail))
      end

      def self.image_raw(data : Bytes, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil) : self
        new(Kind::Image, image: Image.new(DocumentSourceKind.raw(data), media_type, detail))
      end

      def self.image_url(url : String, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil) : self
        new(Kind::Image, image: Image.new(DocumentSourceKind.url(url), media_type, detail))
      end

      def self.audio(data : String, media_type : AudioMediaType? = nil) : self
        new(Kind::Audio, audio: Audio.new(DocumentSourceKind.base64(data), media_type))
      end

      def self.audio_raw(data : Bytes, media_type : AudioMediaType? = nil) : self
        new(Kind::Audio, audio: Audio.new(DocumentSourceKind.raw(data), media_type))
      end

      def self.audio_url(url : String, media_type : AudioMediaType? = nil) : self
        new(Kind::Audio, audio: Audio.new(DocumentSourceKind.url(url), media_type))
      end

      def self.video_base64(data : String, media_type : VideoMediaType? = nil) : self
        new(Kind::Video, video: Video.new(DocumentSourceKind.base64(data), media_type))
      end

      def self.video_raw(data : Bytes, media_type : VideoMediaType? = nil) : self
        new(Kind::Video, video: Video.new(DocumentSourceKind.raw(data), media_type))
      end

      def self.video_url(url : String, media_type : VideoMediaType? = nil) : self
        new(Kind::Video, video: Video.new(DocumentSourceKind.url(url), media_type))
      end

      def self.document(data : String, media_type : DocumentMediaType? = nil) : self
        new(Kind::Document, document: Document.new(DocumentSourceKind.string(data), media_type))
      end

      def self.document_raw(data : Bytes, media_type : DocumentMediaType? = nil) : self
        new(Kind::Document, document: Document.new(DocumentSourceKind.raw(data), media_type))
      end

      def self.document_url(url : String, media_type : DocumentMediaType? = nil) : self
        new(Kind::Document, document: Document.new(DocumentSourceKind.url(url), media_type))
      end
    end

    struct AssistantContent
      enum Kind
        Text
        ToolCall
        Reasoning
        Image
      end

      getter kind : Kind
      getter text : Text?
      getter tool_call : ToolCall?
      getter reasoning : Reasoning?
      getter image : Image?

      def initialize(@kind : Kind, @text : Text? = nil, @tool_call : ToolCall? = nil, @reasoning : Reasoning? = nil, @image : Image? = nil)
      end

      def self.text(text : String) : self
        new(Kind::Text, text: Text.new(text))
      end

      def self.tool_call(id : String, name : String, arguments : JSON::Any) : self
        new(
          Kind::ToolCall,
          nil,
          ToolCall.new(id, ToolFunction.new(name, arguments), nil, nil, nil),
        )
      end

      def self.tool_call_with_call_id(id : String, call_id : String, name : String, arguments : JSON::Any) : self
        new(
          Kind::ToolCall,
          nil,
          ToolCall.new(id, ToolFunction.new(name, arguments), call_id, nil, nil),
        )
      end

      def self.reasoning(reasoning : String) : self
        new(Kind::Reasoning, reasoning: Reasoning.new(reasoning))
      end

      def self.image_base64(data : String, media_type : ImageMediaType? = nil, detail : ImageDetail? = nil) : self
        new(Kind::Image, image: Image.new(DocumentSourceKind.base64(data), media_type, detail))
      end
    end

    struct Message
      enum Role
        User
        Assistant
      end

      getter role : Role
      getter content : Crig::OneOrMany(UserContent | AssistantContent)
      getter id : String?

      def initialize(@role : Role, @content : Crig::OneOrMany(UserContent | AssistantContent), @id : String? = nil)
      end

      def self.user(text : String) : self
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).one(UserContent.text(text)))
      end

      def self.user(content : UserContent) : self
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).one(content))
      end

      def self.user(contents : Array(UserContent)) : self
        mixed = contents.map(&.as(UserContent | AssistantContent))
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).many(mixed))
      end

      def self.user(contents : Crig::OneOrMany(UserContent)) : self
        mixed = contents.to_a.map(&.as(UserContent | AssistantContent))
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).many(mixed))
      end

      def self.assistant(text : String) : self
        new(Role::Assistant, Crig::OneOrMany(UserContent | AssistantContent).one(AssistantContent.text(text)))
      end

      def self.assistant_with_id(id : String, text : String) : self
        new(Role::Assistant, Crig::OneOrMany(UserContent | AssistantContent).one(AssistantContent.text(text)), id)
      end

      def self.tool_result(id : String, content : String) : self
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).one(
          UserContent.tool_result(id, Crig::OneOrMany(ToolResultContent).one(ToolResultContent.text(content)))
        ))
      end

      def self.tool_result_with_call_id(id : String, call_id : String?, content : String) : self
        result_content = Crig::OneOrMany(ToolResultContent).one(ToolResultContent.text(content))
        user_content = call_id ? UserContent.tool_result_with_call_id(id, call_id, result_content) : UserContent.tool_result(id, result_content)
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).one(user_content))
      end

      def self.from(text : Text) : self
        user(text.text)
      end

      def self.from(text : String) : self
        user(text)
      end

      def self.from(image : Image) : self
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).one(UserContent.new(UserContent::Kind::Image, image: image)))
      end

      def self.from(audio : Audio) : self
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).one(UserContent.new(UserContent::Kind::Audio, audio: audio)))
      end

      def self.from(document : Document) : self
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).one(UserContent.new(UserContent::Kind::Document, document: document)))
      end

      def self.from(content : UserContent) : self
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).one(content))
      end

      def self.from(content : AssistantContent) : self
        new(Role::Assistant, Crig::OneOrMany(UserContent | AssistantContent).one(content))
      end

      def self.from(content : Crig::OneOrMany(UserContent)) : self
        content = content.to_a.map(&.as(UserContent | AssistantContent))
        new(Role::User, Crig::OneOrMany(UserContent | AssistantContent).many(content))
      end

      def self.from(content : Crig::OneOrMany(AssistantContent)) : self
        content = content.to_a.map(&.as(UserContent | AssistantContent))
        new(Role::Assistant, Crig::OneOrMany(UserContent | AssistantContent).many(content))
      end

      def self.from(tool_call : ToolCall) : self
        from(AssistantContent.new(AssistantContent::Kind::ToolCall, nil, tool_call))
      end

      def self.from(tool_result : ToolResult) : self
        from(UserContent.new(UserContent::Kind::ToolResult, tool_result: tool_result))
      end

      def self.from(tool_result_content : ToolResultContent) : self
        from(UserContent.new(
          UserContent::Kind::ToolResult,
          tool_result: ToolResult.new("", Crig::OneOrMany(ToolResultContent).one(tool_result_content)),
        ))
      end

      def rag_text : String?
        return unless @role.user?
        @content.each do |item|
          if item.is_a?(UserContent) && item.kind.text?
            text = item.text
            return text.text if text
          end
        end
        nil
      end
    end

    struct ToolChoice
      enum Kind
        Auto
        None
        Required
        Specific
      end

      getter kind : Kind
      getter function_names : Array(String)

      def initialize(@kind : Kind, @function_names : Array(String) = [] of String)
      end

      def self.auto : self
        new(Kind::Auto)
      end

      def self.none : self
        new(Kind::None)
      end

      def self.required : self
        new(Kind::Required)
      end

      def self.specific(function_names : Array(String)) : self
        new(Kind::Specific, function_names)
      end

      def to_json(json : JSON::Builder) : Nil
        json.object do
          case @kind
          in .auto?
            json.field "type", "auto"
          in .none?
            json.field "type", "none"
          in .required?
            json.field "type", "required"
          in .specific?
            json.field "type", "specific"
            json.field "function_names", @function_names
          end
        end
      end

      def self.new(pull : JSON::PullParser)
        type = nil
        function_names = [] of String

        pull.read_begin_object
        until pull.kind.end_object?
          key = pull.read_object_key
          case key
          when "type"
            type = pull.read_string
          when "function_names"
            pull.read_begin_array
            until pull.kind.end_array?
              function_names << pull.read_string
            end
            pull.read_end_array
          else
            pull.skip
          end
        end
        pull.read_end_object

        case type
        when "auto"     then auto
        when "none"     then none
        when "required" then required
        when "specific" then specific(function_names)
        else
          raise MessageError.new("Unknown tool choice type: #{type}")
        end
      end
    end
  end
end
