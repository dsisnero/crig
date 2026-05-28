module Crig
  module Providers
    module Anthropic
      CLAUDE_4_OPUS     = "claude-opus-4-0"
      CLAUDE_4_SONNET   = "claude-sonnet-4-0"
      CLAUDE_3_7_SONNET = "claude-3-7-sonnet-latest"
      CLAUDE_3_5_SONNET = "claude-3-5-sonnet-latest"
      CLAUDE_3_5_HAIKU  = "claude-3-5-haiku-latest"
      CLAUDE_OPUS_4_6   = "claude-opus-4-6"
      CLAUDE_OPUS_4_7   = "claude-opus-4-7"
      CLAUDE_SONNET_4_6 = "claude-sonnet-4-6"
      CLAUDE_HAIKU_4_5  = "claude-haiku-4-5"

      ANTHROPIC_VERSION_2023_01_01 = "2023-01-01"
      ANTHROPIC_VERSION_2023_06_01 = "2023-06-01"

      enum CacheTtl
        OneHour

        def to_wire : String
          "1h"
        end
      end

      struct CacheControl
        enum Kind
          Ephemeral
        end

        getter kind : Kind
        getter ttl : CacheTtl?

        def initialize(@kind : Kind, @ttl : CacheTtl? = nil)
        end

        def self.ephemeral : self
          new(Kind::Ephemeral)
        end

        def self.ephemeral_1h : self
          new(Kind::Ephemeral, CacheTtl::OneHour)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "type", "ephemeral"
            if ttl = @ttl
              json.field "ttl", ttl.to_wire
            end
          end
        end
      end

      enum Role
        User
        Assistant

        def to_wire : String
          to_s.downcase
        end

        def self.from_json_value(value : JSON::Any) : self
          parse(value.as_s)
        end
      end

      enum ImageFormat
        JPEG
        PNG
        GIF
        WEBP

        def to_wire : String
          case self
          in .jpeg? then "image/jpeg"
          in .png?  then "image/png"
          in .gif?  then "image/gif"
          in .webp? then "image/webp"
          end
        end

        def self.from_json_value(value : JSON::Any) : self
          from_wire(value.as_s)
        end

        def self.from_wire(value : String) : self
          case value
          when "image/jpeg" then JPEG
          when "image/png"  then PNG
          when "image/gif"  then GIF
          when "image/webp" then WEBP
          else
            raise Crig::Completion::MessageError.new("Unsupported image media type: #{value}")
          end
        end

        def self.from_core(media_type : Crig::Completion::ImageMediaType) : self
          case media_type
          when Crig::Completion::ImageMediaType::JPEG then JPEG
          when Crig::Completion::ImageMediaType::PNG  then PNG
          when Crig::Completion::ImageMediaType::GIF  then GIF
          when Crig::Completion::ImageMediaType::WEBP then WEBP
          else
            raise Crig::Completion::MessageError.new("Unsupported image media type: #{media_type}")
          end
        end

        def to_core : Crig::Completion::ImageMediaType
          case self
          in .jpeg? then Crig::Completion::ImageMediaType::JPEG
          in .png?  then Crig::Completion::ImageMediaType::PNG
          in .gif?  then Crig::Completion::ImageMediaType::GIF
          in .webp? then Crig::Completion::ImageMediaType::WEBP
          end
        end
      end

      enum DocumentFormat
        PDF

        def to_wire : String
          "application/pdf"
        end

        def self.from_json_value(value : JSON::Any) : self
          case value.as_s
          when "application/pdf" then PDF
          else
            raise Crig::Completion::MessageError.new("Unsupported document media type: #{value.as_s}")
          end
        end
      end

      enum PlainTextMediaType
        Plain

        def to_wire : String
          "text/plain"
        end
      end

      enum SourceType
        BASE64
        URL
        TEXT

        def self.from_core(format : Crig::Completion::ContentFormat) : self
          case format
          in .base64? then BASE64
          in .url?    then URL
          in .string? then TEXT
          end
        end

        def to_core : Crig::Completion::ContentFormat
          case self
          in .base64? then Crig::Completion::ContentFormat::Base64
          in .url?    then Crig::Completion::ContentFormat::Url
          in .text?   then Crig::Completion::ContentFormat::String
          end
        end
      end

      struct ImageSource
        enum Kind
          Base64
          Url
        end

        getter kind : Kind
        getter data : String?
        getter media_type : ImageFormat?
        getter url : String?

        def initialize(@kind : Kind, @data : String? = nil, @media_type : ImageFormat? = nil, @url : String? = nil)
        end

        def self.base64(data : String, media_type : ImageFormat) : self
          new(Kind::Base64, data: data, media_type: media_type)
        end

        def self.url(url : String) : self
          new(Kind::Url, url: url)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["type"].as_s
          when "base64"
            base64(hash["data"].as_s, ImageFormat.from_json_value(hash["media_type"]))
          when "url"
            url(hash["url"].as_s)
          else
            raise Crig::Completion::MessageError.new("Unsupported image source type: #{hash["type"].as_s}")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .base64?
              json.field "type", "base64"
              json.field "data", @data
              json.field "media_type", (@media_type || raise "Missing image media type").to_wire
            in .url?
              json.field "type", "url"
              json.field "url", @url
            end
          end
        end
      end

      struct DocumentSource
        enum Kind
          Base64
          Text
          Url
          File
        end

        getter kind : Kind
        getter data : String?
        getter media_type : DocumentFormat | PlainTextMediaType | Nil
        getter url : String?
        getter file_id : String?

        def initialize(
          @kind : Kind,
          @data : String? = nil,
          @media_type : DocumentFormat | PlainTextMediaType | Nil = nil,
          @url : String? = nil,
          @file_id : String? = nil,
        )
        end

        def self.base64(data : String, media_type : DocumentFormat) : self
          new(Kind::Base64, data: data, media_type: media_type)
        end

        def self.text(data : String, media_type : PlainTextMediaType = PlainTextMediaType::Plain) : self
          new(Kind::Text, data: data, media_type: media_type)
        end

        def self.url(url : String) : self
          new(Kind::Url, url: url)
        end

        def self.file(file_id : String) : self
          new(Kind::File, file_id: file_id)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["type"].as_s
          when "base64"
            base64(hash["data"].as_s, DocumentFormat.from_json_value(hash["media_type"]))
          when "text"
            text(hash["data"].as_s)
          when "url"
            url(hash["url"].as_s)
          when "file"
            file(hash["file_id"].as_s)
          else
            raise Crig::Completion::MessageError.new("Unsupported document source type: #{hash["type"].as_s}")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .base64?
              json.field "type", "base64"
              json.field "data", @data
              json.field "media_type", (@media_type.as?(DocumentFormat) || raise "Missing document format").to_wire
            in .text?
              json.field "type", "text"
              json.field "data", @data
              json.field "media_type", ((@media_type.as?(PlainTextMediaType)) || PlainTextMediaType::Plain).to_wire
            in .url?
              json.field "type", "url"
              json.field "url", @url
            in .file?
              json.field "type", "file"
              json.field "file_id", @file_id
            end
          end
        end
      end

      struct ToolResultContent
        enum Kind
          Text
          Image
        end

        getter kind : Kind
        getter text : String?
        getter image : ImageSource?

        def initialize(@kind : Kind, @text : String? = nil, @image : ImageSource? = nil)
        end

        def self.text(text : String) : self
          new(Kind::Text, text: text)
        end

        def self.image(source : ImageSource) : self
          new(Kind::Image, image: source)
        end

        def self.from_json_value(value : JSON::Any) : self
          if type = value.as_h["type"]?.try(&.as_s?)
            case type
            when "text"
              text(value["text"].as_s)
            when "image"
              image(ImageSource.from_json_value(value["source"]))
            else
              raise Crig::Completion::MessageError.new("Unsupported tool result content type: #{type}")
            end
          elsif inline = value.as_s?
            text(inline)
          else
            raise Crig::Completion::MessageError.new("Unsupported tool result content payload")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .text?
              json.field "type", "text"
              json.field "text", @text
            in .image?
              json.field "type", "image"
              json.field "source" { (@image || raise "Missing tool result image").to_json(json) }
            end
          end
        end

        def to_core : Crig::Completion::ToolResultContent
          case @kind
          in .text?
            Crig::Completion::ToolResultContent.text(@text || "")
          in .image?
            source = @image || raise Crig::Completion::MessageError.new("Missing tool result image")
            case source.kind
            in .base64?
              Crig::Completion::ToolResultContent.image_base64(
                source.data || "",
                source.media_type.as(ImageFormat).to_core,
                nil,
              )
            in .url?
              Crig::Completion::ToolResultContent.image_url(source.url || "", nil, nil)
            end
          end
        end
      end

      ANTHROPIC_RAW_CONTENT_KEY = "anthropic_content"

      struct CitationsConfig
        include JSON::Serializable

        getter enabled : Bool

        def initialize(@enabled : Bool)
        end
      end

      struct Citation
        include JSON::Serializable

        enum Kind
          CharLocation
          PageLocation
          ContentBlockLocation
          SearchResultLocation
          WebSearchResultLocation
          Unknown
        end

        getter kind : Kind
        getter raw : JSON::Any

        def initialize(@kind : Kind, @raw : JSON::Any)
        end

        def self.new(pull : JSON::PullParser)
          raw = JSON::Any.new(pull)
          kind = if hash = raw.as_h?
                   case hash["type"]?.try(&.as_s?)
                   when "char_location"            then Kind::CharLocation
                   when "page_location"            then Kind::PageLocation
                   when "content_block_location"   then Kind::ContentBlockLocation
                   when "search_result_location"   then Kind::SearchResultLocation
                   when "web_search_result_location" then Kind::WebSearchResultLocation
                   else Kind::Unknown
                   end
                 else
                   Kind::Unknown
                 end
          new(kind, raw)
        end
      end

      struct Content
        enum Kind
          Text
          Image
          ToolUse
          ToolResult
          Document
          Thinking
          RedactedThinking
          ServerToolUse
          WebSearchToolResult
        end

        getter kind : Kind
        getter text : String?
        property cache_control : CacheControl?
        getter source : ImageSource | DocumentSource | Nil
        getter id : String?
        getter name : String?
        getter input : JSON::Any?
        getter tool_use_id : String?
        getter tool_result_content : Crig::OneOrMany(ToolResultContent)?
        getter is_error : Bool?
        getter thinking : String?
        getter signature : String?
        getter data : String?
        getter citations : Array(Citation)?
        getter document_title : String?
        getter document_context : String?
        getter document_citations_enabled : Bool?

        def initialize(
          @kind : Kind,
          @text : String? = nil,
          @cache_control : CacheControl? = nil,
          @source : ImageSource | DocumentSource | Nil = nil,
          @id : String? = nil,
          @name : String? = nil,
          @input : JSON::Any? = nil,
          @tool_use_id : String? = nil,
          @tool_result_content : Crig::OneOrMany(ToolResultContent)? = nil,
          @is_error : Bool? = nil,
          @thinking : String? = nil,
          @signature : String? = nil,
          @data : String? = nil,
          @citations : Array(Citation)? = nil,
          @document_title : String? = nil,
          @document_context : String? = nil,
          @document_citations_enabled : Bool? = nil,
        )
        end

        def self.text(text : String, cache_control : CacheControl? = nil) : self
          new(Kind::Text, text: text, cache_control: cache_control)
        end

        def self.image(source : ImageSource, cache_control : CacheControl? = nil) : self
          new(Kind::Image, source: source, cache_control: cache_control)
        end

        def self.tool_use(id : String, name : String, input : JSON::Any) : self
          new(Kind::ToolUse, id: id, name: name, input: input)
        end

        def self.tool_result(tool_use_id : String, content : Crig::OneOrMany(ToolResultContent), is_error : Bool? = nil, cache_control : CacheControl? = nil) : self
          new(Kind::ToolResult, tool_use_id: tool_use_id, tool_result_content: content, is_error: is_error, cache_control: cache_control)
        end

        def self.document(source : DocumentSource, cache_control : CacheControl? = nil) : self
          new(Kind::Document, source: source, cache_control: cache_control)
        end

        def self.thinking(thinking : String, signature : String? = nil) : self
          new(Kind::Thinking, thinking: thinking, signature: signature)
        end

        def self.redacted_thinking(data : String) : self
          new(Kind::RedactedThinking, data: data)
        end

        def self.server_tool_use(id : String, name : String, input : JSON::Any = JSON.parse(%({}))) : self
          new(Kind::ServerToolUse, id: id, name: name, input: input)
        end

        def self.web_search_tool_result(tool_use_id : String) : self
          new(Kind::WebSearchToolResult, tool_use_id: tool_use_id)
        end

        def self.from_json_value(value : JSON::Any) : self
          if string = value.as_s?
            return text(string)
          end

          hash = value.as_h
          case hash["type"].as_s
          when "text"
            citations = hash["citations"]?.try(&.as_a?).try(&.map { |c| Citation.from_json(c.to_json) })
            new(Kind::Text, text: hash["text"].as_s, cache_control: parse_cache_control(hash["cache_control"]?), citations: citations)
          when "image"
            image(ImageSource.from_json_value(hash["source"]), parse_cache_control(hash["cache_control"]?))
          when "tool_use"
            tool_use(hash["id"].as_s, hash["name"].as_s, hash["input"])
          when "tool_result"
            raw_content = hash["content"]
            content = if text = raw_content.as_s?
                        Crig::OneOrMany(ToolResultContent).one(ToolResultContent.text(text))
                      else
                        Crig::OneOrMany(ToolResultContent).many(raw_content.as_a.map { |entry| ToolResultContent.from_json_value(entry) })
                      end
            tool_result(hash["tool_use_id"].as_s, content, hash["is_error"]?.try(&.as_bool), parse_cache_control(hash["cache_control"]?))
          when "document"
            new(
              Kind::Document,
              source: DocumentSource.from_json_value(hash["source"]),
              cache_control: parse_cache_control(hash["cache_control"]?),
              document_title: hash["title"]?.try(&.as_s?),
              document_context: hash["context"]?.try(&.as_s?),
              document_citations_enabled: hash["citations"]?.try(&.as_h?).try(&.["enabled"]?.try(&.as_bool?)),
            )
          when "thinking"
            thinking(hash["thinking"].as_s, hash["signature"]?.try(&.as_s?))
          when "redacted_thinking"
            redacted_thinking(hash["data"].as_s)
          when "server_tool_use"
            server_tool_use(hash["id"].as_s, hash["name"].as_s, hash["input"]? || JSON.parse(%({})))
          when "web_search_tool_result"
            web_search_tool_result(hash["tool_use_id"].as_s)
          else
            raise Crig::Completion::MessageError.new("Unsupported Anthropic content type: #{hash["type"].as_s}")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .text?
              json.field "type", "text"
              json.field "text", @text
              emit_cache_control(json)
            in .image?
              json.field "type", "image"
              json.field "source" { (@source.as?(ImageSource) || raise "Missing image source").to_json(json) }
              emit_cache_control(json)
            in .tool_use?
              json.field "type", "tool_use"
              json.field "id", @id
              json.field "name", @name
              json.field "input" { (@input || JSON::Any.new(nil)).to_json(json) }
            in .tool_result?
              json.field "type", "tool_result"
              json.field "tool_use_id", @tool_use_id
              json.field "content" do
                content = @tool_result_content || raise "Missing tool result content"
                if content.size == 1 && content.first.kind.text?
                  json.string(content.first.text || "")
                else
                  json.array { content.each(&.to_json(json)) }
                end
              end
              json.field "is_error", @is_error unless @is_error.nil?
              emit_cache_control(json)
            in .document?
              json.field "type", "document"
              json.field "source" { (@source.as?(DocumentSource) || raise "Missing document source").to_json(json) }
              emit_cache_control(json)
            in .thinking?
              json.field "type", "thinking"
              json.field "thinking", @thinking
              json.field "signature", @signature unless @signature.nil?
            in .redacted_thinking?
              json.field "type", "redacted_thinking"
              json.field "data", @data
            end
          end
        end

        def to_core_assistant_content : Crig::Completion::AssistantContent
          if @kind.text?
            Crig::Completion::AssistantContent.text(@text || "")
          elsif @kind.tool_use?
            Crig::Completion::AssistantContent.tool_call(@id || "", @name || "", @input || JSON::Any.new(nil))
          elsif @kind.thinking?
            Crig::Completion::AssistantContent.new(
              Crig::Completion::AssistantContent::Kind::Reasoning,
              reasoning: Crig::Completion::Reasoning.new_with_signature(@thinking || "", @signature),
            )
          elsif @kind.redacted_thinking?
            Crig::Completion::AssistantContent.new(
              Crig::Completion::AssistantContent::Kind::Reasoning,
              reasoning: Crig::Completion::Reasoning.redacted(@data || ""),
            )
          else
            raise Crig::Completion::MessageError.new("Content did not contain a message, tool call, or reasoning")
          end
        end

        private def emit_cache_control(json : JSON::Builder) : Nil
          if cache = @cache_control
            json.field "cache_control" { cache.to_json(json) }
          end
        end

        private def self.parse_cache_control(value : JSON::Any?) : CacheControl?
          return unless value
          value["ttl"]?.try(&.as_s?) == "1h" ? CacheControl.ephemeral_1h : CacheControl.ephemeral
        end
      end

      struct Message
        getter role : Role
        getter content : Crig::OneOrMany(Content)

        def initialize(@role : Role, @content : Crig::OneOrMany(Content))
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          content = if raw = hash["content"].as_s?
                      Crig::OneOrMany(Content).one(Content.text(raw))
                    else
                      Crig::OneOrMany(Content).many(hash["content"].as_a.map { |entry| Content.from_json_value(entry) })
                    end
          new(Role.from_json_value(hash["role"]), content)
        end

        def self.from_core_message(message : Crig::Completion::Message) : self
          case message.role
          in .user?
            new(
              Role::User,
              Crig::OneOrMany(Content).many(
                message.content.to_a.map { |entry| content_from_user(entry.as(Crig::Completion::UserContent)) }
              ),
            )
          in .assistant?
            content = message.content.to_a.flat_map do |entry|
              anthropic_content_from_assistant_content(entry.as(Crig::Completion::AssistantContent))
            end
            new(Role::Assistant, Crig::OneOrMany(Content).many(content) || raise Crig::Completion::MessageError.new("Assistant message did not contain Anthropic-compatible content"))
          end
        end

        def to_core_message : Crig::Completion::Message
          case @role
          in .user?
            Crig::Completion::Message.new(
              Crig::Completion::Message::Role::User,
              Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
                @content.to_a.map { |entry| self.class.user_content_to_core(entry).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent) }
              ),
            )
          in .assistant?
            Crig::Completion::Message.new(
              Crig::Completion::Message::Role::Assistant,
              Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
                @content.to_a.map { |entry| entry.to_core_assistant_content.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent) }
              ),
            )
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "role", @role.to_wire
            json.field "content" do
              if @content.size == 1 && @content.first.kind.text? && @content.first.cache_control.nil?
                json.string(@content.first.text || "")
              else
                json.array { @content.each(&.to_json(json)) }
              end
            end
          end
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def self.content_from_user(content : Crig::Completion::UserContent) : Content
          case content.kind
          in .text?
            Content.text(content.text.try(&.text) || "")
          in .tool_result?
            tool_result = content.tool_result || raise Crig::Completion::MessageError.new("Missing tool result content")
            Content.tool_result(
              tool_result.id,
              Crig::OneOrMany(ToolResultContent).many(
                tool_result.content.to_a.map do |entry|
                  case entry.kind
                  in .text?
                    ToolResultContent.text(entry.text.try(&.text) || "")
                  in .image?
                    image = entry.image || raise Crig::Completion::MessageError.new("Missing tool result image")
                    data = image.data.string_value
                    if image.data.kind.base64?
                      media_type = image.media_type || raise Crig::Completion::MessageError.new("Image media type is required")
                      ToolResultContent.image(ImageSource.base64(data || "", ImageFormat.from_core(media_type)))
                    else
                      raise Crig::Completion::MessageError.new("Only base64 strings can be used with the Anthropic API")
                    end
                  end
                end
              ),
            )
          in .image?
            image = content.image || raise Crig::Completion::MessageError.new("Missing image content")
            source = if image.data.kind.base64?
                       media_type = image.media_type || raise Crig::Completion::MessageError.new("Image media type is required for Claude API")
                       ImageSource.base64(image.data.string_value || "", ImageFormat.from_core(media_type))
                     elsif image.data.kind.url?
                       ImageSource.url(image.data.string_value || "")
                     elsif image.data.kind.unknown?
                       raise Crig::Completion::MessageError.new("Image content has no body")
                     else
                       raise Crig::Completion::MessageError.new("Unsupported document type: #{image.data.kind}")
                     end
            Content.image(source)
          in .document?
            document = content.document || raise Crig::Completion::MessageError.new("Missing document content")
            source = if document.data.kind.file_id?
                       DocumentSource.file(document.data.string_value || "")
                     elsif document.data.kind.base64? || document.data.kind.string?
                       media_type = document.media_type
                       if media_type.try(&.pdf?)
                         DocumentSource.base64(document.data.string_value || "", DocumentFormat::PDF)
                       elsif media_type.try(&.txt?)
                         DocumentSource.text(document.data.string_value || "")
                       elsif media_type.nil?
                         DocumentSource.base64(document.data.string_value || "", DocumentFormat::PDF)
                       else
                         raise Crig::Completion::MessageError.new("Anthropic only supports PDF and plain text documents, got: #{Crig::Completion::MimeType.document_to_mime_type(media_type)}")
                       end
                     else
                       raise Crig::Completion::MessageError.new("Only base64 encoded data is supported for PDF documents")
                     end
            Content.document(source)
          in .audio?
            raise Crig::Completion::MessageError.new("Audio is not supported in Anthropic")
          in .video?
            raise Crig::Completion::MessageError.new("Video is not supported in Anthropic")
          end
        end

        # ameba:enable Metrics/CyclomaticComplexity

        # ameba:disable Metrics/CyclomaticComplexity
        def self.user_content_to_core(content : Content) : Crig::Completion::UserContent
          if content.kind.text?
            Crig::Completion::UserContent.text(content.text || "")
          elsif content.kind.tool_result?
            Crig::Completion::UserContent.tool_result(
              content.tool_use_id || "",
              Crig::OneOrMany(Crig::Completion::ToolResultContent).many(
                (content.tool_result_content || raise Crig::Completion::MessageError.new("Missing tool result content")).to_a.map(&.to_core)
              ),
            )
          elsif content.kind.image?
            source = content.source.as(ImageSource)
            case source.kind
            in .base64?
              Crig::Completion::UserContent.image_base64(source.data || "", source.media_type.as(ImageFormat).to_core, nil)
            in .url?
              Crig::Completion::UserContent.image_url(source.url || "", nil, nil)
            end
          elsif content.kind.document?
            source = content.source.as(DocumentSource)
            case source.kind
            in .base64?
              Crig::Completion::UserContent.document(source.data || "", Crig::Completion::DocumentMediaType::PDF)
            in .text?
              Crig::Completion::UserContent.document(source.data || "", Crig::Completion::DocumentMediaType::TXT)
            in .url?
              Crig::Completion::UserContent.document_url(source.url || "", nil)
            in .file?
              Crig::Completion::UserContent.document_file_id(source.file_id || "")
            end
          else
            raise Crig::Completion::MessageError.new("Unsupported content type for User role")
          end
        end

        # ameba:enable Metrics/CyclomaticComplexity

        def self.anthropic_content_from_assistant_content(content : Crig::Completion::AssistantContent) : Array(Content)
          case content.kind
          in .text?
            [Content.text(content.text.try(&.text) || "")]
          in .image?
            raise Crig::Completion::MessageError.new("Anthropic currently doesn't support images.")
          in .tool_call?
            tool_call = content.tool_call || raise Crig::Completion::MessageError.new("Missing assistant tool call")
            [Content.tool_use(tool_call.id, tool_call.function.name, tool_call.function.arguments)]
          in .reasoning?
            reasoning = content.reasoning || raise Crig::Completion::MessageError.new("Missing reasoning content")
            converted = [] of Content
            reasoning.content.each do |block|
              case block.kind
              in .text?
                converted << Content.thinking(block.text || "", block.signature)
              in .summary?
                converted << Content.thinking(block.summary || "")
              in .redacted?, .encrypted?
                converted << Content.redacted_thinking(block.data || "")
              end
            end
            raise Crig::Completion::MessageError.new("Cannot convert empty reasoning content to Anthropic format") if converted.empty?
            converted
          end
        end
      end

      struct ToolDefinition
        getter name : String
        getter description : String?
        getter input_schema : JSON::Any
        getter cache_control : CacheControl?

        def initialize(@name : String, @input_schema : JSON::Any, @description : String? = nil, @cache_control : CacheControl? = nil)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "name", @name
            json.field "description", @description unless @description.nil?
            json.field "input_schema" { @input_schema.to_json(json) }
            json.field "cache_control" { @cache_control.not_nil!.to_json(json) } if @cache_control
          end
        end

        def to_json_value : JSON::Any
          JSON.parse(to_json_build)
        end

        private def to_json_build : String
          JSON.build do |json|
            to_json(json)
          end
        end
      end

      struct Metadata
        getter user_id : String?

        def initialize(@user_id : String? = nil)
        end
      end

      struct ToolChoice
        enum Kind
          Auto
          Any
          None
          Tool
        end

        getter kind : Kind
        getter name : String?

        def initialize(@kind : Kind, @name : String? = nil)
        end

        def self.auto : self
          new(Kind::Auto)
        end

        def self.any : self
          new(Kind::Any)
        end

        def self.none : self
          new(Kind::None)
        end

        def self.tool(name : String) : self
          new(Kind::Tool, name)
        end

        def self.from_core(value : Crig::Completion::ToolChoice) : self
          case value.kind
          in .auto?
            auto
          in .none?
            none
          in .required?
            any
          in .specific?
            if value.function_names.size != 1
              raise Crig::Completion::CompletionError.new("Only one tool may be specified to be used by Claude")
            end
            tool(value.function_names.first)
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            when Kind::Auto
              json.field "type", "auto"
            when Kind::Any
              json.field "type", "any"
            when Kind::None
              json.field "type", "none"
            when Kind::Tool
              json.field "type", "tool"
              json.field "name", (@name || raise Crig::Completion::CompletionError.new("Missing Anthropic tool choice name"))
            end
          end
        end
      end

      def self.calculate_max_tokens(model : String) : Int64?
        case model
        when CLAUDE_OPUS_4_7, CLAUDE_OPUS_4_6
          128_000_i64
        when CLAUDE_SONNET_4_6, CLAUDE_HAIKU_4_5
          64_000_i64
        when .starts_with?("claude-sonnet-4"), .starts_with?("claude-3-7-sonnet")
          64_000_i64
        when .starts_with?("claude-3-5-sonnet"), .starts_with?("claude-3-5-haiku")
          8_192_i64
        when .starts_with?("claude-3-opus"), .starts_with?("claude-3-sonnet"), .starts_with?("claude-3-haiku")
          4_096_i64
        end
      end

      def self.calculate_max_tokens_custom(model : String) : Int64
        calculate_max_tokens(model) || 2_048_i64
      end

      def self.sanitize_schema(schema : JSON::Any) : JSON::Any
        sanitize_schema_value(schema)
      end

      private def self.sanitize_schema_value(schema : JSON::Any) : JSON::Any
        object = schema.as_h?
        return schema unless object

        sanitized = object.dup
        ensure_object_restrictions!(sanitized)
        remove_numeric_constraints!(sanitized)
        sanitize_defs!(sanitized)
        sanitize_properties!(sanitized)
        sanitize_items!(sanitized)
        sanitize_variants!(sanitized)
        JSON.parse(sanitized.to_json)
      end

      private def self.ensure_object_restrictions!(schema : Hash(String, JSON::Any)) : Nil
        is_object_schema = schema["type"]?.try(&.as_s?) == "object" || schema.has_key?("properties")
        if is_object_schema && !schema.has_key?("additionalProperties")
          schema["additionalProperties"] = JSON::Any.new(false)
        end

        properties = schema["properties"]?.try(&.as_h?)
        return unless properties

        required = properties.keys.map { |key| JSON::Any.new(key) }
        schema["required"] = JSON::Any.new(required)
      end

      private def self.remove_numeric_constraints!(schema : Hash(String, JSON::Any)) : Nil
        type = schema["type"]?.try(&.as_s?)
        return unless {"integer", "number"}.includes?(type)

        {"minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"}.each do |key|
          schema.delete(key)
        end
      end

      private def self.sanitize_defs!(schema : Hash(String, JSON::Any)) : Nil
        defs = schema["$defs"]?.try(&.as_h?)
        return unless defs

        defs.each do |key, value|
          defs[key] = sanitize_schema_value(value)
        end
      end

      private def self.sanitize_properties!(schema : Hash(String, JSON::Any)) : Nil
        properties = schema["properties"]?.try(&.as_h?)
        return unless properties

        properties.each do |key, value|
          properties[key] = sanitize_schema_value(value)
        end
      end

      private def self.sanitize_items!(schema : Hash(String, JSON::Any)) : Nil
        items = schema["items"]?
        return unless items

        schema["items"] = sanitize_schema_value(items)
      end

      private def self.sanitize_variants!(schema : Hash(String, JSON::Any)) : Nil
        {"anyOf", "oneOf", "allOf"}.each do |key|
          variants = schema[key]?.try(&.as_a?)
          next unless variants

          schema[key] = JSON::Any.new(variants.map { |variant| sanitize_schema_value(variant) })
        end
      end

      struct OutputFormat
        getter schema : JSON::Any

        def initialize(@schema : JSON::Any)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "type", "json_schema"
            json.field "schema" { @schema.to_json(json) }
          end
        end
      end

      struct OutputConfig
        getter format : OutputFormat

        def initialize(@format : OutputFormat)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "format" { @format.to_json(json) }
          end
        end
      end

      struct AnthropicCompletionRequest
        getter model : String
        getter messages : Array(Message)
        getter max_tokens : Int64
        getter system : Array(SystemContent)
        getter temperature : Float64?
        getter tool_choice : ToolChoice?
        getter tools : Array(ToolDefinition)
        getter output_config : OutputConfig?
        getter additional_params : JSON::Any?

        def initialize(
          @model : String,
          @messages : Array(Message),
          @max_tokens : Int64,
          @system : Array(SystemContent) = [] of SystemContent,
          @temperature : Float64? = nil,
          @tool_choice : ToolChoice? = nil,
          @tools : Array(ToolDefinition) = [] of ToolDefinition,
          @output_config : OutputConfig? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def self.from_params(params : AnthropicRequestParams) : self
          req = params.request
          max_tokens = req.max_tokens || raise Crig::Completion::CompletionError.new("`max_tokens` must be set for Anthropic")

          full_history = [] of Crig::Completion::Message
          if docs = req.normalized_documents
            full_history << docs
          end
          req.chat_history.each { |entry| full_history << entry }

          messages = full_history.map { |entry| Message.from_core_message(entry) }
          tools = req.tools.map { |tool| ToolDefinition.new(tool.name, tool.parameters, tool.description) }

          system = if preamble = req.preamble
                     preamble.empty? ? [] of SystemContent : [SystemContent.text(preamble)]
                   else
                     [] of SystemContent
                   end

          Anthropic.apply_cache_control(system, messages) if params.prompt_caching?

          output_config = req.output_schema.try do |schema|
            OutputConfig.new(OutputFormat.new(Anthropic.sanitize_schema(schema)))
          end

          tool_choice = req.tool_choice.try { |choice| ToolChoice.from_core(choice) }

          unless (additional_params = req.additional_params).nil? || additional_params.as_h?
            raise Crig::Completion::CompletionError.new("Anthropic additional_params must be a JSON object")
          end

          new(
            params.model,
            messages,
            max_tokens,
            system,
            req.temperature,
            tool_choice,
            tools,
            output_config,
            additional_params,
          )
        end

        def to_json_value : JSON::Any
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "messages" do
                json.array { @messages.each(&.to_json(json)) }
              end
              json.field "max_tokens", @max_tokens
              unless @system.empty?
                json.field "system" do
                  json.array { @system.each(&.to_json(json)) }
                end
              end
              json.field "temperature", @temperature unless @temperature.nil?
              if choice = @tool_choice
                json.field "tool_choice" { choice.to_json(json) }
              end
              unless @tools.empty?
                json.field "tools" do
                  json.array { @tools.each(&.to_json(json)) }
                end
              end
              if output_config = @output_config
                json.field "output_config" { output_config.to_json(json) }
              end
            end
          end

          if additional_params = @additional_params
            JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
          else
            payload
          end
        end
      end

      struct Usage
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter input_tokens : Int64
        getter cache_read_input_tokens : Int64?
        getter cache_creation_input_tokens : Int64?
        getter output_tokens : Int64

        def initialize(@input_tokens : Int64, @output_tokens : Int64, @cache_read_input_tokens : Int64? = nil, @cache_creation_input_tokens : Int64? = nil)
        end

        def token_usage : Crig::Completion::Usage?
          input = @input_tokens + (@cache_creation_input_tokens || 0_i64) + (@cache_read_input_tokens || 0_i64)
          Crig::Completion::Usage.new(input, @output_tokens, input + @output_tokens, @cache_read_input_tokens || 0_i64)
        end
      end

      struct CompletionResponse
        getter content : Array(Content)
        getter id : String
        getter model : String
        getter role : String
        getter stop_reason : String?
        getter stop_sequence : String?
        getter usage : Usage

        def initialize(
          @content : Array(Content),
          @id : String,
          @model : String,
          @role : String,
          @usage : Usage,
          @stop_reason : String? = nil,
          @stop_sequence : String? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["content"].as_a.map { |entry| Content.from_json_value(entry) },
            hash["id"].as_s,
            hash["model"].as_s,
            hash["role"].as_s,
            Usage.from_json(hash["usage"].to_json),
            hash["stop_reason"]?.try(&.as_s?),
            hash["stop_sequence"]?.try(&.as_s?),
          )
        end

        private EMPTY_RESPONSE_ERROR = "Response contained no message or tool call (empty)"

        def to_crig_response : Crig::Completion::CompletionResponse(self)
          converted = @content.map(&.to_core_assistant_content)
          choice = if converted.empty?
                     if @stop_reason == "end_turn"
                       Crig::OneOrMany(Crig::Completion::AssistantContent).one(
                         Crig::Completion::AssistantContent.text("")
                       )
                     else
                       raise Crig::Completion::CompletionError.new(EMPTY_RESPONSE_ERROR)
                     end
                   else
                     Crig::OneOrMany(Crig::Completion::AssistantContent).many(converted) ||
                       raise Crig::Completion::CompletionError.new(EMPTY_RESPONSE_ERROR)
                   end
          usage = token_usage || Crig::Completion::Usage.new
          Crig::Completion::CompletionResponse(self).new(choice, usage, self)
        end

        delegate token_usage, to: @usage
      end

      def self.apply_cache_control(system : Array(SystemContent), messages : Array(Message)) : Nil
        unless system.empty?
          system_index = system.size - 1
          last_system = system[system_index]
          last_system.cache_control = CacheControl.ephemeral
          system[system_index] = last_system
        end

        messages.each_with_index do |message, index|
          cleared_content = message.content.to_a.map do |content|
            updated = content
            updated.cache_control = nil
            updated
          end

          messages[index] = Message.new(message.role, Crig::OneOrMany(Content).many(cleared_content))
        end

        unless messages.empty?
          message_index = messages.size - 1
          last_message = messages[message_index]
          content = last_message.content.to_a
          last_content = content.pop
          last_content.cache_control = CacheControl.ephemeral
          content << last_content
          messages[message_index] = Message.new(last_message.role, Crig::OneOrMany(Content).many(content))
        end
      end

      struct SystemContent
        enum Kind
          Text
        end

        getter kind : Kind
        getter text : String
        property cache_control : CacheControl?

        def initialize(@text : String, @cache_control : CacheControl? = nil)
          @kind = Kind::Text
        end

        def self.text(text : String, cache_control : CacheControl? = nil) : self
          new(text, cache_control)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "type", "text"
            json.field "text", @text
            if cache = @cache_control
              json.field "cache_control" { cache.to_json(json) }
            end
          end
        end
      end

      struct CompletionModel
        include Crig::Completion::CompletionModel

        getter client : Client
        getter model : String
        getter default_max_tokens : Int64?
        getter? prompt_caching : Bool
        getter automatic_caching_ttl : CacheTtl?

        def initialize(@client : Client, @model : String, @default_max_tokens : Int64? = nil, @prompt_caching : Bool = false, @automatic_caching_ttl : CacheTtl? = nil)
          @default_max_tokens ||= Anthropic.calculate_max_tokens(@model)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def self.with_model(client : Client, model : String) : self
          new(client, model, Anthropic.calculate_max_tokens_custom(model))
        end

        def with_prompt_caching : self
          self.class.new(@client, @model, @default_max_tokens, true, @automatic_caching_ttl)
        end

        def with_automatic_caching : self
          self.class.new(@client, @model, @default_max_tokens, true, nil)
        end

        def with_automatic_caching_1h : self
          self.class.new(@client, @model, @default_max_tokens, true, CacheTtl::OneHour)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          builder = Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
          if max_tokens = @default_max_tokens
            builder.max_tokens(max_tokens)
          else
            builder
          end
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.chat_span("anthropic", @model, request.preamble, nil)

          request = if request.max_tokens.nil?
                      if max_tokens = @default_max_tokens
                        Crig::Completion::Request::CompletionRequest.new(
                          request.chat_history,
                          model: request.model,
                          preamble: request.preamble,
                          documents: request.documents,
                          tools: request.tools,
                          temperature: request.temperature,
                          max_tokens: max_tokens,
                          tool_choice: request.tool_choice,
                          additional_params: request.additional_params,
                          output_schema: request.output_schema,
                        )
                      else
                        raise Crig::Completion::CompletionError.new("`max_tokens` must be set for Anthropic")
                      end
                    else
                      request
                    end

          payload = AnthropicCompletionRequest.from_params(
            AnthropicRequestParams.new(@model, request, @prompt_caching)
          )
          response = @client.post_json("/v1/messages", payload.to_json_value.to_json)
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          if error = parsed["error"]?
            message = error["message"]?.try(&.as_s?) || body
            raise Crig::Completion::CompletionError.new(message)
          end

          provider_response = CompletionResponse.from_json_value(parsed)
          span.record_response_metadata(provider_response)
          if usage = provider_response.usage
            span.record_token_usage(usage)
          end
          provider_response.to_crig_response
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end
      end

      struct AnthropicRequestParams
        getter model : String
        getter request : Crig::Completion::Request::CompletionRequest
        getter? prompt_caching : Bool

        def initialize(@model : String, @request : Crig::Completion::Request::CompletionRequest, @prompt_caching : Bool = false)
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Anthropic::CompletionModel)

        def completion_model(model : String) : Crig::Providers::Anthropic::CompletionModel
          Crig::Providers::Anthropic::CompletionModel.new(self, model)
        end
      end

      # Telemetry trait implementation for Anthropic CompletionResponse
      struct CompletionResponse
        include Crig::Telemetry::ProviderResponseExt(Content, Usage)

        def response_id : String?
          @id
        end

        def response_model_name : String?
          @model
        end

        def output_messages : Array(Content)
          @content.to_a
        end

        def text_response : String?
          texts = @content.to_a.compact_map do |c|
            c.text if c.kind.text?
          end
          joined = texts.join
          joined.empty? ? nil : joined
        end

        def usage : Usage?
          @usage
        end
      end
    end
  end
end
