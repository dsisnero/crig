require "base64"

module Crig
  module Providers
    module Gemini
      GEMINI_2_5_PRO_PREVIEW_06_05   = "gemini-2.5-pro-preview-06-05"
      GEMINI_2_5_PRO_PREVIEW_05_06   = "gemini-2.5-pro-preview-05-06"
      GEMINI_2_5_PRO_PREVIEW_03_25   = "gemini-2.5-pro-preview-03-25"
      GEMINI_2_5_FLASH_PREVIEW_04_17 = "gemini-2.5-flash-preview-04-17"
      GEMINI_2_5_PRO_EXP_03_25       = "gemini-2.5-pro-exp-03-25"
      GEMINI_2_5_FLASH               = "gemini-2.5-flash"
      GEMINI_3_FLASH_PREVIEW         = "gemini-3-flash-preview"
      GEMINI_3_1_FLASH_LITE_PREVIEW  = "gemini-3.1-flash-lite-preview"
      GEMINI_2_0_FLASH_LITE          = "gemini-2.0-flash-lite"
      GEMINI_2_0_FLASH               = "gemini-2.0-flash"

      enum ThinkingLevel
        Low
        Medium
        High
      end

      TEXT_DOCUMENT_MEDIA_TYPES = {
        Crig::Completion::DocumentMediaType::TXT,
        Crig::Completion::DocumentMediaType::RTF,
        Crig::Completion::DocumentMediaType::HTML,
        Crig::Completion::DocumentMediaType::CSS,
        Crig::Completion::DocumentMediaType::MARKDOWN,
        Crig::Completion::DocumentMediaType::CSV,
        Crig::Completion::DocumentMediaType::XML,
        Crig::Completion::DocumentMediaType::Javascript,
        Crig::Completion::DocumentMediaType::Python,
      }

      enum Role
        User
        Model

        def self.parse(value : String) : self
          case value
          when "user"  then User
          when "model" then Model
          else
            raise Crig::Completion::CompletionError.new("Unknown Gemini role: #{value}")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.string(to_s.downcase)
        end

        def self.new(pull : JSON::PullParser)
          parse(pull.read_string)
        end
      end

      struct Blob
        include JSON::Serializable

        @[JSON::Field(key: "mimeType")]
        getter mime_type : String
        getter data : String

        def initialize(@mime_type : String, @data : String)
        end
      end

      struct FileData
        include JSON::Serializable

        @[JSON::Field(key: "mimeType")]
        getter mime_type : String?
        @[JSON::Field(key: "fileUri")]
        getter file_uri : String

        def initialize(@file_uri : String, @mime_type : String? = nil)
        end
      end

      struct FunctionCall
        include JSON::Serializable

        getter name : String
        getter args : JSON::Any

        def initialize(@name : String, @args : JSON::Any)
        end

        def self.from_tool_call(tool_call : Crig::Completion::ToolCall) : self
          new(tool_call.function.name, tool_call.function.arguments)
        end
      end

      struct FunctionResponseInlineData
        include JSON::Serializable

        @[JSON::Field(key: "mimeType")]
        getter mime_type : String
        getter data : String
        @[JSON::Field(key: "displayName")]
        getter display_name : String?

        def initialize(@mime_type : String, @data : String, @display_name : String? = nil)
        end
      end

      struct FunctionResponsePart
        include JSON::Serializable

        @[JSON::Field(key: "inlineData")]
        getter inline_data : FunctionResponseInlineData?
        @[JSON::Field(key: "fileData")]
        getter file_data : FileData?

        def initialize(@inline_data : FunctionResponseInlineData? = nil, @file_data : FileData? = nil)
        end
      end

      struct FunctionResponse
        include JSON::Serializable

        getter name : String
        getter response : JSON::Any?
        getter parts : Array(FunctionResponsePart)?

        def initialize(@name : String, @response : JSON::Any? = nil, @parts : Array(FunctionResponsePart)? = nil)
        end
      end

      enum ExecutionLanguage
        LanguageUnspecified
        Python

        def self.parse(value : String) : self
          case value
          when "LANGUAGE_UNSPECIFIED" then LanguageUnspecified
          when "PYTHON"               then Python
          else
            raise Crig::Completion::CompletionError.new("Unknown Gemini execution language: #{value}")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.string(
            case self
            in .language_unspecified? then "LANGUAGE_UNSPECIFIED"
            in .python?               then "PYTHON"
            end
          )
        end

        def self.new(pull : JSON::PullParser)
          parse(pull.read_string)
        end
      end

      struct ExecutableCode
        include JSON::Serializable

        getter language : ExecutionLanguage
        getter code : String

        def initialize(@language : ExecutionLanguage, @code : String)
        end
      end

      enum CodeExecutionOutcome
        Unspecified
        Ok
        Failed
        DeadlineExceeded

        def self.parse(value : String) : self
          case value
          when "OUTCOME_UNSPECIFIED"       then Unspecified
          when "OUTCOME_OK"                then Ok
          when "OUTCOME_FAILED"            then Failed
          when "OUTCOME_DEADLINE_EXCEEDED" then DeadlineExceeded
          else
            raise Crig::Completion::CompletionError.new("Unknown Gemini code execution outcome: #{value}")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.string(
            case self
            in .unspecified?       then "OUTCOME_UNSPECIFIED"
            in .ok?                then "OUTCOME_OK"
            in .failed?            then "OUTCOME_FAILED"
            in .deadline_exceeded? then "OUTCOME_DEADLINE_EXCEEDED"
            end
          )
        end

        def self.new(pull : JSON::PullParser)
          parse(pull.read_string)
        end
      end

      struct CodeExecutionResult
        include JSON::Serializable

        getter outcome : CodeExecutionOutcome
        getter output : String?

        def initialize(@outcome : CodeExecutionOutcome, @output : String? = nil)
        end
      end

      struct PartKind
        enum Kind
          Text
          InlineData
          FunctionCall
          FunctionResponse
          FileData
          ExecutableCode
          CodeExecutionResult
        end

        getter kind : Kind
        getter text : String?
        getter inline_data : Blob?
        getter function_call : FunctionCall?
        getter function_response : FunctionResponse?
        getter file_data : FileData?
        getter executable_code : ExecutableCode?
        getter code_execution_result : CodeExecutionResult?

        def initialize(
          @kind : Kind,
          @text : String? = nil,
          @inline_data : Blob? = nil,
          @function_call : FunctionCall? = nil,
          @function_response : FunctionResponse? = nil,
          @file_data : FileData? = nil,
          @executable_code : ExecutableCode? = nil,
          @code_execution_result : CodeExecutionResult? = nil,
        )
        end

        def self.text(text : String) : self
          new(Kind::Text, text: text)
        end

        def self.inline_data(blob : Blob) : self
          new(Kind::InlineData, inline_data: blob)
        end

        def self.function_call(function_call : FunctionCall) : self
          new(Kind::FunctionCall, function_call: function_call)
        end

        def self.function_response(function_response : FunctionResponse) : self
          new(Kind::FunctionResponse, function_response: function_response)
        end

        def self.file_data(file_data : FileData) : self
          new(Kind::FileData, file_data: file_data)
        end

        def self.executable_code(executable_code : ExecutableCode) : self
          new(Kind::ExecutableCode, executable_code: executable_code)
        end

        def self.code_execution_result(code_execution_result : CodeExecutionResult) : self
          new(Kind::CodeExecutionResult, code_execution_result: code_execution_result)
        end

        def to_json(json : JSON::Builder) : Nil
          case @kind
          in .text?
            json.field "text", @text
          in .inline_data?
            json.field "inlineData", @inline_data
          in .function_call?
            json.field "functionCall", @function_call
          in .function_response?
            json.field "functionResponse", @function_response
          in .file_data?
            json.field "fileData", @file_data
          in .executable_code?
            json.field "executableCode", @executable_code
          in .code_execution_result?
            json.field "codeExecutionResult", @code_execution_result
          end
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def self.new(pull : JSON::PullParser)
          kind = nil
          text = nil
          inline_data = nil
          function_call = nil
          function_response = nil
          file_data = nil
          executable_code = nil
          code_execution_result = nil

          pull.read_begin_object
          until pull.kind.end_object?
            key = pull.read_object_key
            case key
            when "text"
              kind = Kind::Text
              text = pull.read_string
            when "inlineData"
              kind = Kind::InlineData
              inline_data = Blob.new(pull)
            when "functionCall"
              kind = Kind::FunctionCall
              function_call = FunctionCall.new(pull)
            when "functionResponse"
              kind = Kind::FunctionResponse
              function_response = FunctionResponse.new(pull)
            when "fileData"
              kind = Kind::FileData
              file_data = FileData.new(pull)
            when "executableCode"
              kind = Kind::ExecutableCode
              executable_code = ExecutableCode.new(pull)
            when "codeExecutionResult"
              kind = Kind::CodeExecutionResult
              code_execution_result = CodeExecutionResult.new(pull)
            else
              pull.skip
            end
          end
          pull.read_end_object

          case kind
          when Kind::Text
            text(text || "")
          when Kind::InlineData
            inline_data(inline_data.as(Blob))
          when Kind::FunctionCall
            function_call(function_call.as(FunctionCall))
          when Kind::FunctionResponse
            function_response(function_response.as(FunctionResponse))
          when Kind::FileData
            file_data(file_data.as(FileData))
          when Kind::ExecutableCode
            executable_code(executable_code.as(ExecutableCode))
          when Kind::CodeExecutionResult
            code_execution_result(code_execution_result.as(CodeExecutionResult))
          else
            raise Crig::Completion::CompletionError.new("Unknown Gemini part kind")
          end
        end
        # ameba:enable Metrics/CyclomaticComplexity
      end

      struct Part
        getter thought : Bool?
        getter thought_signature : String?
        getter part : PartKind
        getter additional_params : JSON::Any?

        def initialize(
          @part : PartKind,
          @thought : Bool? = nil,
          @thought_signature : String? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def self.text(text : String) : self
          new(PartKind.text(text), thought: false)
        end

        def self.from_user_content(content : Crig::Completion::UserContent) : self
          case content.kind
          in .text?
            text = content.text.try(&.text) || ""
            new(PartKind.text(text), thought: false)
          in .tool_result?
            tool_result_to_part(content.tool_result.as(Crig::Completion::ToolResult))
          in .image?
            image_part(content.image.as(Crig::Completion::Image))
          in .audio?
            audio_part(content.audio.as(Crig::Completion::Audio))
          in .video?
            video_part(content.video.as(Crig::Completion::Video))
          in .document?
            document_part(content.document.as(Crig::Completion::Document))
          end
        end

        def self.from_assistant_content(content : Crig::Completion::AssistantContent) : self
          case content.kind
          in .text?
            text(content.text.try(&.text) || "")
          in .image?
            image_part(content.image.as(Crig::Completion::Image))
          in .tool_call?
            tool_call = content.tool_call.as(Crig::Completion::ToolCall)
            new(
              PartKind.function_call(FunctionCall.from_tool_call(tool_call)),
              thought: false,
              thought_signature: tool_call.signature,
            )
          in .reasoning?
            reasoning = content.reasoning.as(Crig::Completion::Reasoning)
            new(
              PartKind.text(reasoning.display_text),
              thought: true,
              thought_signature: reasoning.first_signature,
            )
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            if thought = @thought
              json.field "thought", thought
            end
            if signature = @thought_signature
              json.field "thoughtSignature", signature
            end
            @part.to_json(json)
            if params = @additional_params
              params.as_h.each do |key, value|
                json.field key do
                  value.to_json(json)
                end
              end
            end
          end
        end

        def self.new(pull : JSON::PullParser)
          thought = nil
          thought_signature = nil
          additional = {} of String => JSON::Any
          part_kind = nil

          pull.read_begin_object
          until pull.kind.end_object?
            key = pull.read_object_key
            case key
            when "thought"
              thought = pull.read_bool
            when "thoughtSignature"
              thought_signature = pull.read_string
            when "text", "inlineData", "functionCall", "functionResponse", "fileData", "executableCode", "codeExecutionResult"
              raw = build_single_field_json(key, pull)
              part_kind = PartKind.from_json(raw)
            else
              additional[key] = JSON::Any.new(pull)
            end
          end
          pull.read_end_object

          new(
            part_kind || raise(Crig::Completion::CompletionError.new("Gemini part missing payload")),
            thought: thought,
            thought_signature: thought_signature,
            additional_params: additional.empty? ? nil : JSON.parse(additional.to_json),
          )
        end

        private def self.build_single_field_json(key : String, pull : JSON::PullParser) : String
          String.build do |io|
            JSON.build(io) do |json|
              json.object do
                json.field key do
                  json.raw(pull.read_raw)
                end
              end
            end
          end
        end

        private def self.tool_result_to_part(tool_result : Crig::Completion::ToolResult) : self
          response_json = nil.as(JSON::Any?)
          parts = [] of FunctionResponsePart

          tool_result.content.each do |item|
            case item.kind
            in .text?
              text = item.text.try(&.text) || ""
              parsed = parse_tool_result_text(text)
              response_json = if existing = response_json
                                merge_tool_result_response(existing, parsed)
                              else
                                JSON.parse(%({"result":#{parsed.to_json}}))
                              end
            in .image?
              parts << function_response_part_for_image(item.image.as(Crig::Completion::Image))
            end
          end

          new(
            PartKind.function_response(
              FunctionResponse.new(
                tool_result.id,
                response: response_json,
                parts: parts.empty? ? nil : parts,
              )
            ),
            thought: false,
          )
        end

        private def self.merge_tool_result_response(existing : JSON::Any, parsed : JSON::Any) : JSON::Any
          object = existing.as_h.dup
          object["text"] = parsed
          JSON.parse(object.to_json)
        end

        private def self.parse_tool_result_text(text : String) : JSON::Any
          JSON.parse(text)
        rescue JSON::ParseException
          JSON.parse(text.to_json)
        end

        private def self.function_response_part_for_image(image : Crig::Completion::Image) : FunctionResponsePart
          case image.data.kind
          in .base64?
            media_type = image.media_type || raise Crig::Completion::MessageError.new("Image media type is required for Gemini tool results")
            FunctionResponsePart.new(
              inline_data: FunctionResponseInlineData.new(
                Crig::Completion::MimeType.image_to_mime_type(media_type),
                image.data.string_value || "",
              )
            )
          in .url?
            mime_type = image.media_type.try { |type| Crig::Completion::MimeType.image_to_mime_type(type) }
            FunctionResponsePart.new(
              file_data: FileData.new(
                image.data.string_value || "",
                mime_type: mime_type,
              )
            )
          in .raw?, .string?, .file_id?, .unknown?
            raise Crig::Completion::MessageError.new("Unsupported image source kind for tool results")
          end
        end

        private def self.image_part(image : Crig::Completion::Image) : self
          mime_type = image.media_type || raise Crig::Completion::MessageError.new("A mime type is required for image inputs to Gemini")
          source = image.data
          part_kind = case source.kind
                      in .base64?
                        PartKind.inline_data(
                          Blob.new(
                            Crig::Completion::MimeType.image_to_mime_type(mime_type),
                            source.string_value || "",
                          )
                        )
                      in .url?
                        PartKind.file_data(
                          FileData.new(
                            source.string_value || "",
                            mime_type: Crig::Completion::MimeType.image_to_mime_type(mime_type),
                          )
                        )
                      in .string?
                        raise Crig::Completion::MessageError.new("Strings cannot be used as image files!")
                      in .raw?
                        raise Crig::Completion::MessageError.new("Raw files not supported, encode as base64 first")
                      in .file_id?
                        raise Crig::Completion::MessageError.new("File IDs not supported for image inputs, use URL or base64")
                      in .unknown?
                        raise Crig::Completion::MessageError.new("Content has no body")
                      end

          new(part_kind, thought: false, additional_params: image.additional_params)
        end

        private def self.audio_part(audio : Crig::Completion::Audio) : self
          mime_type = audio.media_type || raise Crig::Completion::MessageError.new("A mime type is required for audio inputs to Gemini")
          source = audio.data
          part_kind = case source.kind
                      in .base64?
                        PartKind.inline_data(
                          Blob.new(
                            Crig::Completion::MimeType.audio_to_mime_type(mime_type),
                            source.string_value || "",
                          )
                        )
                      in .url?
                        PartKind.file_data(
                          FileData.new(
                            source.string_value || "",
                            mime_type: Crig::Completion::MimeType.audio_to_mime_type(mime_type),
                          )
                        )
                      in .string?
                        raise Crig::Completion::MessageError.new("Strings cannot be used as audio files!")
                      in .raw?
                        raise Crig::Completion::MessageError.new("Raw files not supported, encode as base64 first")
                      in .file_id?
                        raise Crig::Completion::MessageError.new("File IDs not supported for audio inputs, use URL or base64")
                      in .unknown?
                        raise Crig::Completion::MessageError.new("Content has no body")
                      end

          new(part_kind, thought: false, additional_params: audio.additional_params)
        end

        private def self.video_part(video : Crig::Completion::Video) : self
          source = video.data
          mime_type = video.media_type.try { |media_type| Crig::Completion::MimeType.video_to_mime_type(media_type) }
          part_kind = case source.kind
                      in .url?
                        url = source.string_value || ""
                        if !url.starts_with?("https://www.youtube.com") && mime_type.nil?
                          raise Crig::Completion::MessageError.new("A mime type is required for non-Youtube video file inputs to Gemini")
                        end
                        PartKind.file_data(FileData.new(url, mime_type: mime_type))
                      in .base64?
                        actual_mime_type = mime_type || raise(Crig::Completion::MessageError.new("A media type is expected for base64 encoded strings"))
                        PartKind.inline_data(Blob.new(actual_mime_type, source.string_value || ""))
                      in .string?
                        raise Crig::Completion::MessageError.new("Strings cannot be used as audio files!")
                      in .raw?
                        raise Crig::Completion::MessageError.new("Raw file data not supported, encode as base64 first")
                      in .file_id?
                        raise Crig::Completion::MessageError.new("File IDs not supported for video inputs, use URL or base64")
                      in .unknown?
                        raise Crig::Completion::MessageError.new("Media type for video is required for Gemini")
                      end

          new(part_kind, thought: false, additional_params: video.additional_params)
        end

        private def self.document_part(document : Crig::Completion::Document) : self
          media_type = document.media_type || raise Crig::Completion::MessageError.new("A mime type is required for document inputs to Gemini")
          source = document.data

          part_kind = if TEXT_DOCUMENT_MEDIA_TYPES.includes?(media_type)
                        text_document_part(media_type, source)
                      elsif media_type.code?
                        raise Crig::Completion::MessageError.new("Unsupported document media type #{media_type}")
                      else
                        binary_document_part(media_type, source)
                      end

          new(part_kind, thought: false)
        end

        private def self.text_document_part(media_type : Crig::Completion::DocumentMediaType, source : Crig::Completion::DocumentSourceKind) : PartKind
          case source.kind
          in .string?
            PartKind.text(source.string_value || "")
          in .base64?
            decoded = Base64.decode_string(source.string_value || "")
            PartKind.text(decoded)
          in .url?
            PartKind.file_data(
              FileData.new(
                source.string_value || "",
                mime_type: Crig::Completion::MimeType.document_to_mime_type(media_type),
              )
            )
          in .raw?
            raise Crig::Completion::MessageError.new("Raw files not supported, encode as base64 first")
          in .file_id?
            raise Crig::Completion::MessageError.new("File IDs not supported for document inputs, use URL or base64")
          in .unknown?
            raise Crig::Completion::MessageError.new("Document has no body")
          end
        end

        private def self.binary_document_part(media_type : Crig::Completion::DocumentMediaType, source : Crig::Completion::DocumentSourceKind) : PartKind
          mime_type = Crig::Completion::MimeType.document_to_mime_type(media_type)
          case source.kind
          in .url?
            PartKind.file_data(FileData.new(source.string_value || "", mime_type: mime_type))
          in .base64?, .string?
            PartKind.inline_data(Blob.new(mime_type, source.string_value || ""))
          in .raw?
            raise Crig::Completion::MessageError.new("Raw files not supported, encode as base64 first")
          in .file_id?
            raise Crig::Completion::MessageError.new("File IDs not supported for document inputs, use URL or base64")
          in .unknown?
            raise Crig::Completion::MessageError.new("Document has no body")
          end
        end
      end

      struct Content
        getter parts : Array(Part)
        getter role : Role?

        def initialize(@parts : Array(Part), @role : Role? = nil)
        end

        def self.from_message(msg : Crig::Completion::Message) : self
          case msg.role
          in .user?
            new(
              msg.content.to_a.compact_map { |content| content.as?(Crig::Completion::UserContent) }.map { |content| Part.from_user_content(content) },
              role: Role::User
            )
          in .assistant?
            new(
              msg.content.to_a.compact_map { |content| content.as?(Crig::Completion::AssistantContent) }.map { |content| Part.from_assistant_content(content) },
              role: Role::Model
            )
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "parts", @parts
            if role = @role
              json.field "role", role
            end
          end
        end

        def self.new(pull : JSON::PullParser)
          parts = [] of Part
          role = nil

          pull.read_begin_object
          until pull.kind.end_object?
            key = pull.read_object_key
            case key
            when "parts"
              pull.read_begin_array
              until pull.kind.end_array?
                parts << Part.new(pull)
              end
              pull.read_end_array
            when "role"
              role = Role.new(pull)
            else
              pull.skip
            end
          end
          pull.read_end_object

          new(parts, role: role)
        end
      end

      class Schema
        include JSON::Serializable

        getter type : String
        getter format : String?
        getter description : String?
        getter nullable : Bool?
        @[JSON::Field(key: "enum")]
        getter enum_values : Array(String)?
        @[JSON::Field(key: "maxItems")]
        getter max_items : Int32?
        @[JSON::Field(key: "minItems")]
        getter min_items : Int32?
        getter properties : Hash(String, Schema)?
        getter required : Array(String)?
        getter items : Schema?

        def initialize(
          @type : String,
          @format : String? = nil,
          @description : String? = nil,
          @nullable : Bool? = nil,
          @enum_values : Array(String)? = nil,
          @max_items : Int32? = nil,
          @min_items : Int32? = nil,
          @properties : Hash(String, Schema)? = nil,
          @required : Array(String)? = nil,
          @items : Schema? = nil,
        )
        end

        def self.try_from(value : JSON::Any) : self
          flattened = Gemini.flatten_schema(value)
          object = flattened.as_h?
          raise Crig::Completion::CompletionError.new("Expected a JSON object for Schema") unless object

          props_source = schema_source_for_properties(object)
          schema_type = Gemini.infer_type(object)
          items = object["items"]?.try { |entry| try_from(entry) }
          items ||= Schema.new("string") if schema_type == "array" && items.nil?

          new(
            schema_type,
            format: object["format"]?.try(&.as_s?),
            description: object["description"]?.try(&.as_s?),
            nullable: object["nullable"]?.try(&.as_bool?),
            enum_values: object["enum"]?.try(&.as_a?).try { |entries| entries.compact_map(&.as_s?) },
            max_items: object["maxItems"]?.try(&.as_i?).try(&.to_i32),
            min_items: object["minItems"]?.try(&.as_i?).try(&.to_i32),
            properties: props_source["properties"]?.try(&.as_h?).try do |entries|
              entries.each_with_object({} of String => Schema) do |(key, entry), memo|
                memo[key] = try_from(entry)
              end
            end,
            required: props_source["required"]?.try(&.as_a?).try { |entries| entries.compact_map(&.as_s?) },
            items: items
          )
        end

        private def self.schema_source_for_properties(object : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
          return object if object["properties"]?

          Gemini.extract_schema_from_composition(object["anyOf"]?) ||
            Gemini.extract_schema_from_composition(object["oneOf"]?) ||
            Gemini.extract_schema_from_composition(object["allOf"]?) ||
            object
        end
      end

      struct FunctionDeclaration
        include JSON::Serializable

        getter name : String
        getter description : String
        getter parameters : Schema?

        def initialize(@name : String, @description : String, @parameters : Schema? = nil)
        end
      end

      struct Tool
        include JSON::Serializable

        @[JSON::Field(key: "functionDeclarations")]
        getter function_declarations : Array(FunctionDeclaration)

        def initialize(@function_declarations : Array(FunctionDeclaration))
        end

        def self.from_tool_definition(tool : Crig::Completion::ToolDefinition) : self
          parameters = if tool.parameters == JSON.parse(%({"type":"object","properties":{}}))
                         nil
                       else
                         Schema.try_from(tool.parameters)
                       end

          new([FunctionDeclaration.new(tool.name, tool.description, parameters)])
        end

        def self.from_tool_definitions(tools : Array(Crig::Completion::ToolDefinition)) : self
          declarations = tools.map do |tool|
            parameters = if tool.parameters == JSON.parse(%({"type":"object","properties":{}}))
                           nil
                         else
                           Schema.try_from(tool.parameters)
                         end
            FunctionDeclaration.new(tool.name, tool.description, parameters)
          rescue ex
            raise Crig::Completion::CompletionError.new("Tool '#{tool.name}' could not be converted to a schema: #{ex.message}")
          end

          new(declarations)
        end
      end

      enum FunctionCallingModeTag
        Auto
        None
        Any
      end

      struct FunctionCallingMode
        getter mode : FunctionCallingModeTag
        getter allowed_function_names : Array(String)?

        def initialize(@mode : FunctionCallingModeTag, @allowed_function_names : Array(String)? = nil)
        end

        def self.from_tool_choice(value : Crig::Completion::ToolChoice) : self
          case value.kind
          in .auto?
            new(FunctionCallingModeTag::Auto)
          in .none?
            new(FunctionCallingModeTag::None)
          in .required?
            new(FunctionCallingModeTag::Any)
          in .specific?
            new(FunctionCallingModeTag::Any, value.function_names)
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "mode", @mode.to_s.upcase
            if names = @allowed_function_names
              json.field "allowedFunctionNames", names
            end
          end
        end
      end

      struct ToolConfig
        include JSON::Serializable

        @[JSON::Field(key: "functionCallingConfig")]
        getter function_calling_config : FunctionCallingMode?

        def initialize(@function_calling_config : FunctionCallingMode? = nil)
        end
      end

      struct GenerationConfig
        include JSON::Serializable

        @[JSON::Field(key: "stopSequences")]
        property stop_sequences : Array(String)?
        @[JSON::Field(key: "temperature")]
        property temperature : Float64?
        @[JSON::Field(key: "candidateCount")]
        property candidate_count : Int32?
        @[JSON::Field(key: "maxOutputTokens")]
        property max_output_tokens : Int64?
        @[JSON::Field(key: "topP")]
        property top_p : Float64?
        @[JSON::Field(key: "topK")]
        property top_k : Int32?
        @[JSON::Field(key: "presencePenalty")]
        property presence_penalty : Float64?
        @[JSON::Field(key: "frequencyPenalty")]
        property frequency_penalty : Float64?
        @[JSON::Field(key: "responseMimeType")]
        property response_mime_type : String?
        @[JSON::Field(key: "responseSchema")]
        property response_schema : Schema?
        @[JSON::Field(key: "_responseJsonSchema")]
        property internal_response_json_schema : JSON::Any?
        @[JSON::Field(key: "responseJsonSchema")]
        property response_json_schema : JSON::Any?
        @[JSON::Field(key: "responseLogprobs")]
        property response_logprobs : Bool?
        @[JSON::Field(key: "logprobs")]
        property logprobs : Int32?
        @[JSON::Field(key: "thinkingConfig")]
        property thinking_config : ThinkingConfig?
        @[JSON::Field(key: "imageConfig")]
        property image_config : ImageConfig?

        def initialize(
          @stop_sequences : Array(String)? = nil,
          @temperature : Float64? = nil,
          @candidate_count : Int32? = nil,
          @max_output_tokens : Int64? = nil,
          @top_p : Float64? = nil,
          @top_k : Int32? = nil,
          @presence_penalty : Float64? = nil,
          @frequency_penalty : Float64? = nil,
          @response_mime_type : String? = nil,
          @response_schema : Schema? = nil,
          @internal_response_json_schema : JSON::Any? = nil,
          @response_json_schema : JSON::Any? = nil,
          @response_logprobs : Bool? = nil,
          @logprobs : Int32? = nil,
          @thinking_config : ThinkingConfig? = nil,
          @image_config : ImageConfig? = nil,
        )
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def empty? : Bool
          @stop_sequences.nil? && @temperature.nil? && @candidate_count.nil? && @max_output_tokens.nil? &&
            @top_p.nil? && @top_k.nil? && @presence_penalty.nil? && @frequency_penalty.nil? &&
            @response_mime_type.nil? && @response_schema.nil? && @internal_response_json_schema.nil? &&
            @response_json_schema.nil? && @response_logprobs.nil? && @logprobs.nil? &&
            @thinking_config.nil? && @image_config.nil?
        end
        # ameba:enable Metrics/CyclomaticComplexity
      end

      struct AdditionalParameters
        getter generation_config : GenerationConfig?
        getter additional_params : JSON::Any?

        def initialize(@generation_config : GenerationConfig? = nil, @additional_params : JSON::Any? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          generation_config = hash["generationConfig"]?.try { |entry| GenerationConfig.from_json(entry.to_json) }
          additional_hash = hash.reject { |key, _| key == "generationConfig" }
          additional_params = additional_hash.empty? ? nil : JSON.parse(additional_hash.to_json)
          new(generation_config, additional_params)
        end

        def with_config(cfg : GenerationConfig) : self
          self.class.new(cfg, @additional_params)
        end

        def with_params(params : JSON::Any) : self
          self.class.new(@generation_config, params)
        end
      end

      struct GenerateContentRequest
        getter contents : Array(Content)
        getter tools : Array(Tool)?
        getter tool_config : ToolConfig?
        getter generation_config : GenerationConfig?
        getter system_instruction : Content?
        getter additional_params : JSON::Any?

        def initialize(
          @contents : Array(Content),
          @tools : Array(Tool)? = nil,
          @tool_config : ToolConfig? = nil,
          @generation_config : GenerationConfig? = nil,
          @system_instruction : Content? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "contents", @contents
            if tools = @tools
              json.field "tools", tools
            end
            if tool_config = @tool_config
              json.field "toolConfig", tool_config
            end
            if generation_config = @generation_config
              json.field "generationConfig", generation_config
            end
            if system_instruction = @system_instruction
              json.field "systemInstruction", system_instruction
            end
            if additional_params = @additional_params
              additional_params.as_h.each do |key, value|
                json.field key do
                  value.to_json(json)
                end
              end
            end
          end
        end
      end

      enum FinishReason
        FinishReasonUnspecified
        Stop
        MaxTokens
        Safety
        Recitation
        Language
        Other
        Blocklist
        ProhibitedContent
        Spii
        MalformedFunctionCall

        def self.new(pull : JSON::PullParser)
          parse(pull.read_string)
        end
      end

      enum HarmProbability
        HarmProbabilityUnspecified
        Negligible
        Low
        Medium
        High

        def self.parse(value : String) : self
          case value
          when "HARM_PROBABILITY_UNSPECIFIED" then HarmProbabilityUnspecified
          when "NEGLIGIBLE"                   then Negligible
          when "LOW"                          then Low
          when "MEDIUM"                       then Medium
          when "HIGH"                         then High
          else
            raise Crig::Completion::CompletionError.new("Unknown Gemini harm probability: #{value}")
          end
        end

        def self.new(pull : JSON::PullParser)
          parse(pull.read_string)
        end
      end

      enum HarmCategory
        HarmCategoryUnspecified
        HarmCategoryDerogatory
        HarmCategoryToxicity
        HarmCategoryViolence
        HarmCategorySexually
        HarmCategoryMedical
        HarmCategoryDangerous
        HarmCategoryHarassment
        HarmCategoryHateSpeech
        HarmCategorySexuallyExplicit
        HarmCategoryDangerousContent
        HarmCategoryCivicIntegrity

        # ameba:disable Metrics/CyclomaticComplexity
        def self.parse(value : String) : self
          case value
          when "HARM_CATEGORY_UNSPECIFIED" then HarmCategoryUnspecified
          when "HARM_CATEGORY_DEROGATORY"  then HarmCategoryDerogatory
          when "HARM_CATEGORY_TOXICITY"    then HarmCategoryToxicity
          when "HARM_CATEGORY_VIOLENCE"    then HarmCategoryViolence
          when "HARM_CATEGORY_SEXUALLY"    then HarmCategorySexually
          when "HARM_CATEGORY_MEDICAL"     then HarmCategoryMedical
          when "HARM_CATEGORY_DANGEROUS"   then HarmCategoryDangerous
          when "HARM_CATEGORY_HARASSMENT"  then HarmCategoryHarassment
          when "HARM_CATEGORY_HATE_SPEECH" then HarmCategoryHateSpeech
          when "HARM_CATEGORY_SEXUALLY_EXPLICIT"
            HarmCategorySexuallyExplicit
          when "HARM_CATEGORY_DANGEROUS_CONTENT"
            HarmCategoryDangerousContent
          when "HARM_CATEGORY_CIVIC_INTEGRITY"
            HarmCategoryCivicIntegrity
          else
            raise Crig::Completion::CompletionError.new("Unknown Gemini harm category: #{value}")
          end
        end

        # ameba:enable Metrics/CyclomaticComplexity

        def self.new(pull : JSON::PullParser)
          parse(pull.read_string)
        end
      end

      struct SafetyRating
        include JSON::Serializable

        getter category : HarmCategory
        getter probability : HarmProbability

        def initialize(@category : HarmCategory, @probability : HarmProbability)
        end
      end

      struct CitationSource
        include JSON::Serializable

        @[JSON::Field(key: "uri")]
        getter uri : String?
        @[JSON::Field(key: "startIndex")]
        getter start_index : Int32?
        @[JSON::Field(key: "endIndex")]
        getter end_index : Int32?
        getter license : String?

        def initialize(@uri : String? = nil, @start_index : Int32? = nil, @end_index : Int32? = nil, @license : String? = nil)
        end
      end

      struct CitationMetadata
        include JSON::Serializable

        @[JSON::Field(key: "citationSources")]
        getter citation_sources : Array(CitationSource)

        def initialize(@citation_sources : Array(CitationSource))
        end
      end

      struct LogProbCandidate
        include JSON::Serializable

        getter token : String
        @[JSON::Field(key: "tokenId")]
        getter token_id : String
        @[JSON::Field(key: "logProbability")]
        getter log_probability : Float64

        def initialize(@token : String, @token_id : String, @log_probability : Float64)
        end
      end

      struct TopCandidate
        include JSON::Serializable

        getter candidates : Array(LogProbCandidate)

        def initialize(@candidates : Array(LogProbCandidate))
        end
      end

      struct LogprobsResult
        include JSON::Serializable

        @[JSON::Field(key: "topCandidates")]
        getter top_candidates : Array(TopCandidate)
        @[JSON::Field(key: "chosenCandidates")]
        getter chosen_candidates : Array(LogProbCandidate)

        def initialize(@top_candidates : Array(TopCandidate), @chosen_candidates : Array(LogProbCandidate))
        end
      end

      enum BlockReason
        BlockReasonUnspecified
        Safety
        Other
        Blocklist
        ProhibitedContent

        def self.parse(value : String) : self
          case value
          when "BLOCK_REASON_UNSPECIFIED" then BlockReasonUnspecified
          when "SAFETY"                   then Safety
          when "OTHER"                    then Other
          when "BLOCKLIST"                then Blocklist
          when "PROHIBITED_CONTENT"       then ProhibitedContent
          else
            raise Crig::Completion::CompletionError.new("Unknown Gemini block reason: #{value}")
          end
        end

        def self.new(pull : JSON::PullParser)
          parse(pull.read_string)
        end
      end

      struct PromptFeedback
        include JSON::Serializable

        @[JSON::Field(key: "blockReason")]
        getter block_reason : BlockReason?
        @[JSON::Field(key: "safetyRatings")]
        getter safety_ratings : Array(SafetyRating)?

        def initialize(@block_reason : BlockReason? = nil, @safety_ratings : Array(SafetyRating)? = nil)
        end
      end

      struct UsageMetadata
        include JSON::Serializable

        @[JSON::Field(key: "promptTokenCount")]
        getter prompt_token_count : Int32
        @[JSON::Field(key: "cachedContentTokenCount")]
        getter cached_content_token_count : Int32?
        @[JSON::Field(key: "candidatesTokenCount")]
        getter candidates_token_count : Int32?
        @[JSON::Field(key: "totalTokenCount")]
        getter total_token_count : Int32
        @[JSON::Field(key: "thoughtsTokenCount")]
        getter thoughts_token_count : Int32?

        def initialize(
          @prompt_token_count : Int32,
          @cached_content_token_count : Int32? = nil,
          @candidates_token_count : Int32? = nil,
          @total_token_count : Int32 = 0,
          @thoughts_token_count : Int32? = nil,
        )
        end

        def token_usage : Crig::Completion::Usage
          input_tokens = @prompt_token_count.to_i64
          output_tokens = (@cached_content_token_count || 0).to_i64 +
                          (@candidates_token_count || 0).to_i64 +
                          (@thoughts_token_count || 0).to_i64
          Crig::Completion::Usage.new(
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            total_tokens: input_tokens + output_tokens,
            cached_input_tokens: (@cached_content_token_count || 0).to_i64,
          )
        end
      end

      struct ModalityTokenCount
        include JSON::Serializable

        @[JSON::Field(key: "modality")]
        getter modality : Modality
        @[JSON::Field(key: "tokenCount")]
        getter token_count : Int32

        def initialize(@modality : Modality, @token_count : Int32)
        end
      end

      enum Modality
        MODALITY_UNSPECIFIED
        TEXT
        IMAGE
        VIDEO
        AUDIO
        DOCUMENT
      end

      enum TrafficType
        TRAFFIC_TYPE_UNSPECIFIED
        ON_DEMAND
        PROVISIONED_THROUGHPUT
      end

      struct ContentCandidate
        include JSON::Serializable

        getter content : Content?
        @[JSON::Field(key: "finishReason")]
        getter finish_reason : FinishReason?
        @[JSON::Field(key: "safetyRatings")]
        getter safety_ratings : Array(SafetyRating)?
        @[JSON::Field(key: "citationMetadata")]
        getter citation_metadata : CitationMetadata?
        @[JSON::Field(key: "tokenCount")]
        getter token_count : Int32?
        @[JSON::Field(key: "avgLogprobs")]
        getter avg_logprobs : Float64?
        @[JSON::Field(key: "logprobsResult")]
        getter logprobs_result : LogprobsResult?
        getter index : Int32?
        @[JSON::Field(key: "finishMessage")]
        getter finish_message : String?

        def initialize(
          @content : Content? = nil,
          @finish_reason : FinishReason? = nil,
          @safety_ratings : Array(SafetyRating)? = nil,
          @citation_metadata : CitationMetadata? = nil,
          @token_count : Int32? = nil,
          @avg_logprobs : Float64? = nil,
          @logprobs_result : LogprobsResult? = nil,
          @index : Int32? = nil,
          @finish_message : String? = nil,
        )
        end
      end

      struct ThinkingConfig
        include JSON::Serializable

        @[JSON::Field(key: "thinkingBudget")]
        getter thinking_budget : Int32
        @[JSON::Field(key: "includeThoughts")]
        getter include_thoughts : Bool?

        def initialize(@thinking_budget : Int32, @include_thoughts : Bool? = nil)
        end
      end

      struct ImageConfig
        include JSON::Serializable

        @[JSON::Field(key: "aspectRatio")]
        getter aspect_ratio : String?
        @[JSON::Field(key: "imageSize")]
        getter image_size : String?

        def initialize(@aspect_ratio : String? = nil, @image_size : String? = nil)
        end
      end

      struct CodeExecution
        include JSON::Serializable
      end

      enum HarmBlockThreshold
        HarmBlockThresholdUnspecified
        BlockLowAndAbove
        BlockMediumAndAbove
        BlockOnlyHigh
        BlockNone
        Off

        def self.parse(value : String) : self
          case value
          when "HARM_BLOCK_THRESHOLD_UNSPECIFIED" then HarmBlockThresholdUnspecified
          when "BLOCK_LOW_AND_ABOVE"              then BlockLowAndAbove
          when "BLOCK_MEDIUM_AND_ABOVE"           then BlockMediumAndAbove
          when "BLOCK_ONLY_HIGH"                  then BlockOnlyHigh
          when "BLOCK_NONE"                       then BlockNone
          when "OFF"                              then Off
          else
            raise Crig::Completion::CompletionError.new("Unknown Gemini harm block threshold: #{value}")
          end
        end

        def self.new(pull : JSON::PullParser)
          parse(pull.read_string)
        end
      end

      struct SafetySetting
        include JSON::Serializable

        getter category : HarmCategory
        getter threshold : HarmBlockThreshold

        def initialize(@category : HarmCategory, @threshold : HarmBlockThreshold)
        end
      end

      struct GenerateContentResponse
        include JSON::Serializable

        @[JSON::Field(key: "responseId")]
        getter response_id : String
        getter candidates : Array(ContentCandidate)
        @[JSON::Field(key: "promptFeedback")]
        getter prompt_feedback : PromptFeedback?
        @[JSON::Field(key: "usageMetadata")]
        getter usage_metadata : UsageMetadata?
        @[JSON::Field(key: "modelVersion")]
        getter model_version : String?

        def initialize(
          @response_id : String,
          @candidates : Array(ContentCandidate),
          @prompt_feedback : PromptFeedback? = nil,
          @usage_metadata : UsageMetadata? = nil,
          @model_version : String? = nil,
        )
        end

        def to_completion_response : Crig::Completion::CompletionResponse(self)
          candidate = @candidates.first? || raise Crig::Completion::CompletionError.new("No response candidates in response")
          content = candidate.content || raise Crig::Completion::CompletionError.new(
            "Gemini candidate missing content (finish_reason=#{candidate.finish_reason || "unknown"}, finish_message=#{candidate.finish_message || "no finish message provided"})"
          )

          choice = content.parts.map do |part|
            case part.part.kind
            in .text?
              text = part.part.text || ""
              if part.thought
                Crig::Completion::AssistantContent.new(
                  Crig::Completion::AssistantContent::Kind::Reasoning,
                  reasoning: Crig::Completion::Reasoning.new_with_signature(text, part.thought_signature),
                )
              else
                Crig::Completion::AssistantContent.text(text)
              end
            in .inline_data?
              inline_data = part.part.inline_data.as(Blob)
              media_type = Crig::Completion::MimeType.from_mime_type(inline_data.mime_type)
              if media_type && media_type.kind.image?
                Crig::Completion::AssistantContent.image_base64(
                  inline_data.data,
                  media_type.image,
                  Crig::Completion::ImageDetail::Auto,
                )
              else
                raise Crig::Completion::CompletionError.new("Unsupported media type #{inline_data.mime_type}")
              end
            in .function_call?
              function_call = part.part.function_call.as(FunctionCall)
              Crig::Completion::AssistantContent.new(
                Crig::Completion::AssistantContent::Kind::ToolCall,
                tool_call: Crig::Completion::ToolCall.new(
                  function_call.name,
                  Crig::Completion::ToolFunction.new(function_call.name, function_call.args),
                  nil,
                  part.thought_signature,
                ),
              )
            in .function_response?, .file_data?, .executable_code?, .code_execution_result?
              raise Crig::Completion::CompletionError.new("Response did not contain a message or tool call")
            end
          end

          usage = @usage_metadata ? @usage_metadata.try(&.token_usage) : Crig::Completion::Usage.new

          Crig::Completion::CompletionResponse(self).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).many(choice),
            usage || Crig::Completion::Usage.new,
            self,
            @response_id,
          )
        end
      end

      struct CompletionModel
        include Crig::Completion::CompletionModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def self.with_model(client : Client, model : String) : self
          new(client, model)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def create_request_body(request : Crig::Completion::Request::CompletionRequest) : GenerateContentRequest
          Gemini.create_request_body(request)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.chat_span("gemini", @model, request.preamble, nil)

          request_model = Gemini.resolve_request_model(@model, request)
          payload = Gemini.create_request_body(request)
          response = @client.post_json(Gemini.completion_endpoint(request_model), payload.to_json)
          body = response.body

          if response.status_code >= 400
            raise Crig::Completion::CompletionError.new(body)
          end

          result = GenerateContentResponse.from_json(body).to_completion_response
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end
      end

      def self.create_request_body(completion_request : Crig::Completion::Request::CompletionRequest) : GenerateContentRequest
        full_history = [] of Crig::Completion::Message
        if documents_message = completion_request.normalized_documents
          full_history << documents_message
        end
        full_history.concat(completion_request.chat_history.to_a)

        additional_params_json = completion_request.additional_params || JSON.parse("{}")
        params = AdditionalParameters.from_json_value(additional_params_json)
        generation_config = params.generation_config

        if schema = completion_request.output_schema
          generation_config ||= GenerationConfig.new
          generation_config.response_mime_type = "application/json"
          generation_config.response_json_schema = schema
        end

        if generation_config
          generation_config.temperature = completion_request.temperature if completion_request.temperature
          generation_config.max_output_tokens = completion_request.max_tokens if completion_request.max_tokens
        end

        system_instruction = completion_request.preamble.try do |preamble|
          Content.new([Part.text(preamble)], role: Role::Model)
        end

        tools = completion_request.tools.empty? ? nil : [Tool.from_tool_definitions(completion_request.tools)]
        tool_config = completion_request.tool_choice.try do |choice|
          ToolConfig.new(FunctionCallingMode.from_tool_choice(choice))
        end

        GenerateContentRequest.new(
          full_history.map { |message| Content.from_message(message) },
          tools: tools,
          tool_config: tool_config,
          generation_config: generation_config,
          system_instruction: system_instruction,
          additional_params: params.additional_params,
        )
      end

      def self.resolve_request_model(default_model : String, completion_request : Crig::Completion::Request::CompletionRequest) : String
        completion_request.model || default_model
      end

      def self.completion_endpoint(model : String) : String
        "/v1beta/models/#{model}:generateContent"
      end

      def self.streaming_endpoint(model : String) : String
        "/v1beta/models/#{model}:streamGenerateContent"
      end

      def self.flatten_schema(schema : JSON::Any) : JSON::Any
        object = schema.as_h?
        return schema unless object

        defs = object["$defs"]? || object["definitions"]?
        return schema unless defs

        defs_object = defs.as_h?
        raise Crig::Completion::CompletionError.new("$defs must be an object") unless defs_object

        resolved = resolve_refs(schema, defs_object)
        resolved_object = resolved.as_h?
        if resolved_object
          cleaned = resolved_object.reject { |key, _| key == "$defs" || key == "definitions" }
          JSON.parse(cleaned.to_json)
        else
          resolved
        end
      end

      def self.resolve_refs(value : JSON::Any, defs : Hash(String, JSON::Any)) : JSON::Any
        if object = value.as_h?
          if ref_value = object["$ref"]?
            ref_name = parse_ref_path(ref_value.as_s)
            definition = defs[ref_name]? || raise(Crig::Completion::CompletionError.new("Reference not found: #{ref_value.as_s}"))
            return resolve_refs(definition, defs)
          end

          resolved = object.each_with_object({} of String => JSON::Any) do |(key, entry), memo|
            memo[key] = resolve_refs(entry, defs)
          end
          JSON.parse(resolved.to_json)
        elsif array = value.as_a?
          JSON.parse(array.map { |entry| resolve_refs(entry, defs) }.to_json)
        else
          value
        end
      end

      def self.parse_ref_path(ref_str : String) : String
        if fragment = ref_str.lchop?('#')
          return fragment.lchop("/$defs/") if fragment.starts_with?("/$defs/")
          return fragment.lchop("/definitions/") if fragment.starts_with?("/definitions/")
          raise Crig::Completion::CompletionError.new("Unsupported reference format: #{ref_str}")
        end

        raise Crig::Completion::CompletionError.new("Only fragment references (#/...) are supported: #{ref_str}")
      end

      def self.extract_type(type_value : JSON::Any) : String?
        if value = type_value.as_s?
          value
        elsif values = type_value.as_a?
          values.first?.try(&.as_s?)
        end
      end

      def self.extract_type_from_composition(composition : JSON::Any?) : String?
        composition.try(&.as_a?).try do |entries|
          entries.each do |entry|
            object = entry.as_h?
            next unless object
            type_value = object["type"]?
            next unless type_value
            next if type_value.try(&.as_s?) == "null"
            return extract_type(type_value) || (object["properties"]? ? "object" : nil)
          end
          nil
        end
      end

      def self.extract_schema_from_composition(composition : JSON::Any?) : Hash(String, JSON::Any)?
        composition.try(&.as_a?).try do |entries|
          entries.each do |entry|
            object = entry.as_h?
            next unless object
            type_value = object["type"]?
            next unless type_value
            next if type_value.as_s? == "null"
            return object
          end
          nil
        end
      end

      def self.infer_type(object : Hash(String, JSON::Any)) : String
        if type = object["type"]?.try { |value| extract_type(value) }
          return type
        end
        if type = extract_type_from_composition(object["anyOf"]?)
          return type
        end
        if type = extract_type_from_composition(object["oneOf"]?)
          return type
        end
        if type = extract_type_from_composition(object["allOf"]?)
          return type
        end
        return "object" if object["properties"]?
        ""
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Gemini::CompletionModel)
      end
    end
  end
end
