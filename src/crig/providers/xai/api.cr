module Crig
  module Providers
    module XAI
      struct ToolDefinition
        include JSON::Serializable

        @[JSON::Field(key: "type")]
        getter type : String
        getter function : Crig::Completion::ToolDefinition

        def initialize(@function : Crig::Completion::ToolDefinition, @type : String = "function")
        end

        def self.from(tool : Crig::Completion::ToolDefinition) : self
          new(tool)
        end
      end

      struct ApiError
        include JSON::Serializable

        getter error : String
        getter code : String

        def initialize(@error : String, @code : String)
        end

        def message : String
          "Code `#{@code}`: #{@error}"
        end
      end

      struct ApiResponse(T)
        getter ok : T?
        getter error : ApiError?

        def initialize(@ok : T? = nil, @error : ApiError? = nil)
        end

        def self.from_json_value(value : JSON::Any, & : JSON::Any -> T) : self
          if value["error"]? && value["code"]?
            new(error: ApiError.from_json(value.to_json))
          else
            new(ok: yield value)
          end
        end
      end

      enum Role
        System
        User
        Assistant

        def to_wire : String
          to_s.downcase
        end
      end

      struct ContentItem
        enum Kind
          Text
          Image
          File
        end

        getter kind : Kind
        getter text : String?
        getter image_url : String?
        getter detail : String?
        getter file_url : String?
        getter file_data : String?

        def initialize(
          @kind : Kind,
          @text : String? = nil,
          @image_url : String? = nil,
          @detail : String? = nil,
          @file_url : String? = nil,
          @file_data : String? = nil,
        )
        end

        def self.text(text : String) : self
          new(Kind::Text, text: text)
        end

        def self.image(image_url : String, detail : String? = nil) : self
          new(Kind::Image, image_url: image_url, detail: detail)
        end

        def self.file(file_url : String? = nil, file_data : String? = nil) : self
          new(Kind::File, file_url: file_url, file_data: file_data)
        end

        def to_json_value : JSON::Any
          OpenAI.build_json_any do |json|
            json.object do
              case @kind
              in .text?
                json.field "type", "input_text"
                json.field "text", @text
              in .image?
                json.field "type", "input_image"
                json.field "image_url", @image_url
                if detail = @detail
                  json.field "detail", detail
                end
              in .file?
                json.field "type", "input_file"
                if file_url = @file_url
                  json.field "file_url", file_url
                end
                if file_data = @file_data
                  json.field "file_data", file_data
                end
              end
            end
          end
        end
      end

      struct Content
        enum Kind
          Text
          Array
        end

        getter kind : Kind
        getter text : String?
        getter items : Array(ContentItem)?

        def initialize(@kind : Kind, @text : String? = nil, @items : Array(ContentItem)? = nil)
        end

        def self.text(text : String) : self
          new(Kind::Text, text: text)
        end

        def self.array(items : Array(ContentItem)) : self
          new(Kind::Array, items: items)
        end

        def to_json_value : JSON::Any
          case @kind
          in .text?
            JSON::Any.new(@text || "")
          in .array?
            JSON.parse((@items || [] of ContentItem).map(&.to_json_value).to_json)
          end
        end
      end

      struct Message
        enum Kind
          Message
          FunctionCall
          FunctionCallOutput
          Reasoning
        end

        getter kind : Kind
        getter role : Role?
        getter content : Content?
        getter call_id : String?
        getter name : String?
        getter arguments : String?
        getter output : String?
        getter id : String?
        getter summary : Array(Crig::Providers::OpenAI::ReasoningSummary)?
        getter encrypted_content : String?

        def initialize(
          @kind : Kind,
          @role : Role? = nil,
          @content : Content? = nil,
          @call_id : String? = nil,
          @name : String? = nil,
          @arguments : String? = nil,
          @output : String? = nil,
          @id : String? = nil,
          @summary : Array(Crig::Providers::OpenAI::ReasoningSummary)? = nil,
          @encrypted_content : String? = nil,
        )
        end

        def self.system(content : String) : self
          new(Kind::Message, role: Role::System, content: Content.text(content))
        end

        def self.user(content : String) : self
          new(Kind::Message, role: Role::User, content: Content.text(content))
        end

        def self.user_with_content(content : Array(ContentItem)) : self
          new(Kind::Message, role: Role::User, content: Content.array(content))
        end

        def self.assistant(content : String) : self
          new(Kind::Message, role: Role::Assistant, content: Content.text(content))
        end

        def self.function_call(call_id : String, name : String, arguments : String) : self
          new(Kind::FunctionCall, call_id: call_id, name: name, arguments: arguments)
        end

        def self.function_call_output(call_id : String, output : String) : self
          new(Kind::FunctionCallOutput, call_id: call_id, output: output)
        end

        def self.reasoning(
          id : String,
          summary : Array(Crig::Providers::OpenAI::ReasoningSummary),
          encrypted_content : String?,
        ) : self
          new(Kind::Reasoning, id: id, summary: summary, encrypted_content: encrypted_content)
        end

        def to_json_value : JSON::Any
          OpenAI.build_json_any do |json|
            json.object do
              case @kind
              in .message?
                json.field "type", "message"
                json.field "role", (@role || Role::User).to_wire
                json.field "content" do
                  (@content || Content.text("")).to_json_value.to_json(json)
                end
              in .function_call?
                json.field "type", "function_call"
                json.field "call_id", @call_id
                json.field "name", @name
                json.field "arguments", @arguments
              in .function_call_output?
                json.field "type", "function_call_output"
                json.field "call_id", @call_id
                json.field "output", @output
              in .reasoning?
                json.field "type", "reasoning"
                json.field "id", @id
                json.field "summary" do
                  json.array do
                    (@summary || [] of Crig::Providers::OpenAI::ReasoningSummary).each(&.to_json_value.to_json(json))
                  end
                end
                if encrypted_content = @encrypted_content
                  json.field "encrypted_content", encrypted_content
                end
              end
            end
          end
        end

        def self.from_completion_message(msg : Crig::Completion::Message) : Array(self)
          build_from_completion_message(msg)
        end

        private def self.build_from_completion_message(msg : Crig::Completion::Message) : Array(self)
          case msg.role
          in .user?
            convert_user_message(msg)
          in .assistant?
            convert_assistant_message(msg)
          end
        end

        private def self.convert_user_message(msg : Crig::Completion::Message) : Array(self)
          items = [] of Message
          text_parts = [] of String
          content_items = [] of ContentItem
          has_media = false

          msg.content.each do |content|
            user_content = content.as(Crig::Completion::UserContent)
            case user_content.kind
            in .text?
              text_parts << require_user_text(user_content)
            in .image?
              has_media = true
              content_items << image_item(user_content.image || raise Crig::Completion::CompletionError.new("Missing user image"))
            in .tool_result?
              flush_user_content(items, text_parts, content_items, has_media)
              has_media = false
              tool_result = user_content.tool_result || raise Crig::Completion::CompletionError.new("Missing tool result")
              call_id = tool_result.call_id || raise Crig::Completion::CompletionError.new("Tool result `call_id` is required for xAI Responses API")
              output = tool_result.content.to_a.map do |result_content|
                case result_content.kind
                when .text?
                  require_tool_result_text(result_content)
                when .image?
                  raise Crig::Completion::CompletionError.new("xAI does not support images in tool results")
                end
              end.join('\n')
              items << function_call_output(call_id, output)
            in .document?
              has_media = true
              content_items << document_item(user_content.document || raise Crig::Completion::CompletionError.new("Missing user document"))
            in .audio?
              raise Crig::Completion::CompletionError.new("xAI does not support audio")
            in .video?
              raise Crig::Completion::CompletionError.new("xAI does not support video")
            end
          end

          flush_user_content(items, text_parts, content_items, has_media)
          items
        end

        private def self.flush_user_content(
          items : Array(Message),
          text_parts : Array(String),
          content_items : Array(ContentItem),
          has_media : Bool,
        ) : Nil
          if has_media
            merged = text_parts.map { |text| ContentItem.text(text) }
            merged.concat(content_items)
            items << user_with_content(merged) unless merged.empty?
          elsif !text_parts.empty?
            items << user(text_parts.join('\n'))
          end
          text_parts.clear
          content_items.clear
        end

        private def self.convert_assistant_message(msg : Crig::Completion::Message) : Array(self)
          items = [] of Message
          text_parts = [] of String

          msg.content.each do |content|
            assistant_content = content.as(Crig::Completion::AssistantContent)
            case assistant_content.kind
            in .text?
              text_parts << require_assistant_text(assistant_content)
            in .tool_call?
              flush_assistant_text(items, text_parts)
              tool_call = assistant_content.tool_call || raise Crig::Completion::CompletionError.new("Missing assistant tool call")
              call_id = tool_call.call_id || raise Crig::Completion::CompletionError.new("Assistant tool call `call_id` is required for xAI Responses API")
              items << function_call(call_id, tool_call.function.name, tool_call.function.arguments.to_json)
            in .reasoning?
              flush_assistant_text(items, text_parts)
              items << reasoning_item(assistant_content.reasoning || raise Crig::Completion::CompletionError.new("Missing assistant reasoning"))
            in .image?
              raise Crig::Completion::CompletionError.new("xAI does not support images in assistant content")
            end
          end

          flush_assistant_text(items, text_parts)
          items
        end

        private def self.flush_assistant_text(items : Array(Message), text_parts : Array(String)) : Nil
          unless text_parts.empty?
            items << assistant(text_parts.join('\n'))
            text_parts.clear
          end
        end

        private def self.require_user_text(content : Crig::Completion::UserContent) : String
          text = content.text || raise Crig::Completion::CompletionError.new("Missing user text content")
          text.text
        end

        private def self.require_tool_result_text(content : Crig::Completion::ToolResultContent) : String
          text = content.text || raise Crig::Completion::CompletionError.new("Missing tool-result text content")
          text.text
        end

        private def self.require_assistant_text(content : Crig::Completion::AssistantContent) : String
          text = content.text || raise Crig::Completion::CompletionError.new("Missing assistant text content")
          text.text
        end

        private def self.reasoning_item(reasoning : Crig::Completion::Reasoning) : Message
          id = reasoning.id || raise Crig::Completion::CompletionError.new("Assistant reasoning `id` is required for xAI Responses replay")
          encrypted_content = nil.as(String?)
          summary = [] of Crig::Providers::OpenAI::ReasoningSummary

          reasoning.content.each do |reasoning_content|
            case reasoning_content.kind
            in .text?
              summary << Crig::Providers::OpenAI::ReasoningSummary.new(reasoning_content.text || "")
            in .summary?
              summary << Crig::Providers::OpenAI::ReasoningSummary.new(reasoning_content.summary || "")
            in .redacted?, .encrypted?
              encrypted_content ||= reasoning_content.data
            end
          end

          reasoning(id, summary, encrypted_content)
        end

        private def self.image_item(image : Crig::Completion::Image) : ContentItem
          url = case image.data.kind
                when .url?
                  image.data.string_value
                when .base64?
                  media_type = image.media_type ? Crig::Completion::MimeType.image_to_mime_type(image.media_type.as(Crig::Completion::ImageMediaType)) : "image/png"
                  "data:#{media_type};base64,#{image.data.string_value || ""}"
                when .raw?, .string?
                  raise Crig::Completion::CompletionError.new("xAI does not support raw image data; use base64 or URL")
                end
          url ||= raise Crig::Completion::CompletionError.new("xAI image URL missing")
          ContentItem.image(url, image.detail.try(&.to_s.downcase))
        end

        private def self.document_item(document : Crig::Completion::Document) : ContentItem
          item = case document.data.kind
                 when .url?
                   url = document.data.string_value || raise Crig::Completion::CompletionError.new("xAI document URL missing")
                   ContentItem.file(file_url: url)
                 when .base64?
                   media_type = document.media_type ? Crig::Completion::MimeType.document_to_mime_type(document.media_type.as(Crig::Completion::DocumentMediaType)) : "application/pdf"
                   ContentItem.file(file_data: "data:#{media_type};base64,#{document.data.string_value || ""}")
                 when .string?
                   ContentItem.text(document.data.string_value || "")
                 when .raw?
                   raise Crig::Completion::CompletionError.new("xAI does not support raw document data; use base64 or URL")
                 end
          item || raise Crig::Completion::CompletionError.new("Unsupported xAI document content")
        end
      end
    end
  end
end
