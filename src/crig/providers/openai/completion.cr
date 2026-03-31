require "http/client"

module Crig
  module Providers
    module OpenAI
      GPT_5_2                    = "gpt-5.2"
      GPT_5_1                    = "gpt-5.1"
      GPT_5                      = "gpt-5"
      GPT_5_MINI                 = "gpt-5-mini"
      GPT_5_NANO                 = "gpt-5-nano"
      GPT_4_5_PREVIEW            = "gpt-4.5-preview"
      GPT_4_5_PREVIEW_2025_02_27 = "gpt-4.5-preview-2025-02-27"
      GPT_4O_2024_11_20          = "gpt-4o-2024-11-20"
      GPT_4O                     = "gpt-4o"
      GPT_4O_MINI                = "gpt-4o-mini"
      GPT_4O_2024_05_13          = "gpt-4o-2024-05-13"
      GPT_4_TURBO                = "gpt-4-turbo"
      GPT_4_TURBO_2024_04_09     = "gpt-4-turbo-2024-04-09"
      GPT_4_TURBO_PREVIEW        = "gpt-4-turbo-preview"
      GPT_4_0125_PREVIEW         = "gpt-4-0125-preview"
      GPT_4_1106_PREVIEW         = "gpt-4-1106-preview"
      GPT_4_1106_VISION_PREVIEW  = "gpt-4-1106-vision-preview"
      GPT_4_VISION_PREVIEW       = "gpt-4-vision-preview"
      GPT_4                      = "gpt-4"
      GPT_4_0613                 = "gpt-4-0613"
      GPT_4_32K                  = "gpt-4-32k"
      GPT_4_32K_0613             = "gpt-4-32k-0613"
      O4_MINI_2025_04_16         = "o4-mini-2025-04-16"
      O4_MINI                    = "o4-mini"
      O3                         = "o3"
      O3_MINI                    = "o3-mini"
      O3_MINI_2025_01_31         = "o3-mini-2025-01-31"
      O1_PRO                     = "o1-pro"
      O1                         = "o1"
      O1_2024_12_17              = "o1-2024-12-17"
      O1_PREVIEW                 = "o1-preview"
      O1_PREVIEW_2024_09_12      = "o1-preview-2024-09-12"
      O1_MINI                    = "o1-mini"
      O1_MINI_2024_09_12         = "o1-mini-2024-09-12"
      GPT_4_1_MINI               = "gpt-4.1-mini"
      GPT_4_1_NANO               = "gpt-4.1-nano"
      GPT_4_1_2025_04_14         = "gpt-4.1-2025-04-14"
      GPT_4_1                    = "gpt-4.1"

      struct OpenAIUsage
        include JSON::Serializable

        struct PromptTokensDetails
          include JSON::Serializable

          @[JSON::Field(key: "cached_tokens")]
          getter cached_tokens : Int32

          def initialize(@cached_tokens : Int32 = 0)
          end
        end

        @[JSON::Field(key: "prompt_tokens")]
        getter prompt_tokens : Int32
        @[JSON::Field(key: "total_tokens")]
        getter total_tokens : Int32
        @[JSON::Field(key: "prompt_tokens_details")]
        getter prompt_tokens_details : PromptTokensDetails?

        def initialize(@prompt_tokens : Int32 = 0, @total_tokens : Int32 = 0, @prompt_tokens_details : PromptTokensDetails? = nil)
        end

        def to_crig_usage : Crig::Completion::Usage
          Crig::Completion::Usage.new(
            input_tokens: @prompt_tokens.to_i64,
            output_tokens: (@total_tokens - @prompt_tokens).to_i64,
            total_tokens: @total_tokens.to_i64,
            cached_input_tokens: @prompt_tokens_details.try(&.cached_tokens.to_i64) || 0_i64,
          )
        end
      end

      module Chat
        struct AudioAssistant
          include JSON::Serializable

          getter id : String

          def initialize(@id : String)
          end
        end

        enum SystemContentType
          Text

          def to_wire : String
            "text"
          end
        end

        struct SystemContent
          include JSON::Serializable

          @[JSON::Field(key: "type")]
          getter type : SystemContentType = SystemContentType::Text
          getter text : String

          def initialize(@text : String, @type : SystemContentType = SystemContentType::Text)
          end

          def self.from_string(text : String) : self
            new(text)
          end
        end

        struct AssistantContent
          enum Kind
            Text
            Refusal
          end

          getter kind : Kind
          getter text : String

          def initialize(@kind : Kind, @text : String)
          end

          def self.text(text : String) : self
            new(Kind::Text, text)
          end

          def self.refusal(text : String) : self
            new(Kind::Refusal, text)
          end

          def self.from_string(text : String) : self
            self.text(text)
          end

          def to_json_value : JSON::Any
            OpenAI.build_json_any do |json|
              json.object do
                case @kind
                in .text?
                  json.field "type", "text"
                  json.field "text", @text
                in .refusal?
                  json.field "type", "refusal"
                  json.field "refusal", @text
                end
              end
            end
          end

          def to_completion_content : Crig::Completion::AssistantContent
            Crig::Completion::AssistantContent.text(@text)
          end
        end

        struct ImageUrl
          include JSON::Serializable

          getter url : String
          getter detail : String = "auto"

          def initialize(@url : String, @detail : String = "auto")
          end
        end

        struct InputAudio
          include JSON::Serializable

          getter data : String
          getter format : String

          def initialize(@data : String, @format : String)
          end
        end

        struct UserContent
          enum Kind
            Text
            Image
            Audio
          end

          getter kind : Kind
          getter text : String?
          getter image_url : ImageUrl?
          getter input_audio : InputAudio?

          def initialize(@kind : Kind, @text : String? = nil, @image_url : ImageUrl? = nil, @input_audio : InputAudio? = nil)
          end

          def self.text(text : String) : self
            new(Kind::Text, text: text)
          end

          def self.image(url : String, detail : String = "auto") : self
            new(Kind::Image, image_url: ImageUrl.new(url, detail))
          end

          def self.audio(data : String, format : String) : self
            new(Kind::Audio, input_audio: InputAudio.new(data, format))
          end

          def self.from_string(text : String) : self
            self.text(text)
          end

          def to_json_value : JSON::Any
            OpenAI.build_json_any do |json|
              json.object do
                case @kind
                in .text?
                  json.field "type", "text"
                  json.field "text", @text
                in .image?
                  image = @image_url || raise Crig::Completion::CompletionError.new("Missing OpenAI image content")
                  json.field "type", "image_url"
                  json.field "image_url" do
                    image.to_json(json)
                  end
                in .audio?
                  audio = @input_audio || raise Crig::Completion::CompletionError.new("Missing OpenAI input audio content")
                  json.field "type", "input_audio"
                  json.field "input_audio" do
                    audio.to_json(json)
                  end
                end
              end
            end
          end
        end

        struct ToolResultContent
          include JSON::Serializable

          @[JSON::Field(key: "type")]
          getter type : ToolResultContentType = ToolResultContentType::Text
          getter text : String

          def initialize(@text : String, @type : ToolResultContentType = ToolResultContentType::Text)
          end

          def self.from_string(text : String) : self
            new(text)
          end
        end

        struct ToolResultContentValue
          enum Kind
            Array
            String
          end

          getter kind : Kind
          getter array_value : Array(ToolResultContent)?
          getter string_value : String?

          def initialize(@kind : Kind, @array_value : Array(ToolResultContent)? = nil, @string_value : String? = nil)
          end

          def self.from_string(text : String, use_array_format : Bool = false) : self
            if use_array_format
              new(Kind::Array, array_value: [ToolResultContent.from_string(text)])
            else
              new(Kind::String, string_value: text)
            end
          end

          def as_text : String
            case @kind
            in .array?
              (@array_value || [] of ToolResultContent).map(&.text).join('\n')
            in .string?
              @string_value || ""
            end
          end

          def to_array : self
            return self if @kind.array?
            self.class.from_string(@string_value || "", true)
          end

          def to_json_value : JSON::Any
            case @kind
            in .array?
              OpenAI.build_json_any do |json|
                json.array do
                  (@array_value || [] of ToolResultContent).each(&.to_json(json))
                end
              end
            in .string?
              JSON::Any.new(@string_value || "")
            end
          end
        end

        enum ToolType
          Function

          def to_wire : String
            "function"
          end
        end

        struct Function
          getter name : String
          getter arguments : JSON::Any

          def initialize(@name : String, @arguments : JSON::Any)
          end

          def to_json_value : JSON::Any
            OpenAI.build_json_any do |json|
              json.object do
                json.field "name", @name
                json.field "arguments", @arguments.to_json
              end
            end
          end
        end

        struct ToolCall
          getter id : String
          getter type : ToolType
          getter function : Function

          def initialize(@id : String, @function : Function, @type : ToolType = ToolType::Function)
          end

          def to_json_value : JSON::Any
            OpenAI.build_json_any do |json|
              json.object do
                json.field "id", @id
                json.field "type", @type.to_wire
                json.field "function" do
                  @function.to_json_value.to_json(json)
                end
              end
            end
          end
        end

        struct FunctionDefinition
          getter name : String
          getter description : String
          getter parameters : JSON::Any
          getter? strict : Bool?

          def initialize(@name : String, @description : String, @parameters : JSON::Any, @strict : Bool? = nil)
          end

          def to_json_value : JSON::Any
            OpenAI.build_json_any do |json|
              json.object do
                json.field "name", @name
                json.field "description", @description
                json.field "parameters" do
                  @parameters.to_json(json)
                end
                unless @strict.nil?
                  json.field "strict", @strict
                end
              end
            end
          end
        end

        struct ToolDefinition
          getter type : String
          getter function : FunctionDefinition

          def initialize(@function : FunctionDefinition, @type : String = "function")
          end

          def self.from_tool(tool : Crig::Completion::ToolDefinition) : self
            new(FunctionDefinition.new(tool.name, tool.description, tool.parameters))
          end

          def with_strict : self
            self.class.new(
              FunctionDefinition.new(
                @function.name,
                @function.description,
                OpenAI.sanitize_schema(@function.parameters),
                true,
              ),
              @type,
            )
          end

          def to_json_value : JSON::Any
            OpenAI.build_json_any do |json|
              json.object do
                json.field "type", @type
                json.field "function" do
                  @function.to_json_value.to_json(json)
                end
              end
            end
          end
        end

        enum ToolChoice
          Auto
          None
          Required

          def to_wire : String
            to_s.downcase
          end
        end

        struct Message
          enum Kind
            System
            User
            Assistant
            ToolResult
          end

          getter kind : Kind
          getter system_content : Crig::OneOrMany(SystemContent)?
          getter user_content : Crig::OneOrMany(UserContent)?
          getter assistant_content : Array(AssistantContent)
          getter refusal : String?
          getter audio : AudioAssistant?
          getter name : String?
          getter tool_calls : Array(ToolCall)
          getter tool_call_id : String?
          getter tool_result_content : ToolResultContentValue?

          def initialize(
            @kind : Kind,
            @system_content : Crig::OneOrMany(SystemContent)? = nil,
            @user_content : Crig::OneOrMany(UserContent)? = nil,
            @assistant_content : Array(AssistantContent) = [] of AssistantContent,
            @refusal : String? = nil,
            @audio : AudioAssistant? = nil,
            @name : String? = nil,
            @tool_calls : Array(ToolCall) = [] of ToolCall,
            @tool_call_id : String? = nil,
            @tool_result_content : ToolResultContentValue? = nil,
          )
          end

          def self.system(content : String) : self
            new(Kind::System, system_content: Crig::OneOrMany(SystemContent).one(SystemContent.from_string(content)))
          end

          def self.user(content : Crig::OneOrMany(UserContent), name : String? = nil) : self
            new(Kind::User, user_content: content, name: name)
          end

          def self.assistant(content : Array(AssistantContent), tool_calls : Array(ToolCall) = [] of ToolCall, refusal : String? = nil, audio : AudioAssistant? = nil, name : String? = nil) : self
            new(Kind::Assistant, assistant_content: content, tool_calls: tool_calls, refusal: refusal, audio: audio, name: name)
          end

          def self.tool_result(tool_call_id : String, content : ToolResultContentValue) : self
            new(Kind::ToolResult, tool_call_id: tool_call_id, tool_result_content: content)
          end

          def self.from_json_value(value : JSON::Any) : self
            hash = value.as_h
            case hash["role"].as_s
            when "system", "developer"
              content = parse_system_content(hash["content"])
              new(Kind::System, system_content: content, name: hash["name"]?.try(&.as_s?))
            when "user"
              content = parse_user_content(hash["content"])
              new(Kind::User, user_content: content, name: hash["name"]?.try(&.as_s?))
            when "assistant"
              assistant_content = parse_assistant_content(hash["content"]?)
              tool_calls = hash["tool_calls"]?.try(&.as_a?).try(&.map { |entry| parse_tool_call(entry) }) || [] of ToolCall
              new(
                Kind::Assistant,
                assistant_content: assistant_content,
                refusal: hash["refusal"]?.try(&.as_s?),
                audio: hash["audio"]?.try { |audio| AudioAssistant.from_json(audio.to_json) },
                name: hash["name"]?.try(&.as_s?),
                tool_calls: tool_calls,
              )
            when "tool"
              content = parse_tool_result_content(hash["content"])
              new(Kind::ToolResult, tool_call_id: hash["tool_call_id"].as_s, tool_result_content: content)
            else
              raise Crig::Completion::CompletionError.new("Unsupported OpenAI message role: #{hash["role"].as_s}")
            end
          end

          # ameba:disable Metrics/CyclomaticComplexity
          def self.from_core_message(
            message : Crig::Completion::Message,
            tool_result_array_content : Bool = false,
          ) : Array(self)
            case message.role
            in .user?
              tool_results = [] of self
              other_content = [] of UserContent

              message.content.each do |content|
                next unless user_content = content.as?(Crig::Completion::UserContent)
                case user_content.kind
                in .text?
                  text = user_content.text.try(&.text) || ""
                  other_content << UserContent.text(text)
                in .image?
                  image = user_content.image || raise Crig::Completion::CompletionError.new("Missing image content")
                  case image.data.kind
                  in .url?
                    url = image.data.string_value || raise Crig::Completion::CompletionError.new("OpenAI image URL is missing")
                    other_content << UserContent.image(url, image.detail.try(&.to_s.downcase) || "auto")
                  in .base64?
                    media_type = image.media_type.try { |value| Crig::Completion::MimeType.image_to_mime_type(value) } ||
                                 raise Crig::Completion::CompletionError.new("OpenAI Image URI must have media type")
                    detail = image.detail || raise Crig::Completion::CompletionError.new("OpenAI image URI must have image detail")
                    data = image.data.string_value || raise Crig::Completion::CompletionError.new("OpenAI base64 image is missing")
                    other_content << UserContent.image("data:#{media_type};base64,#{data}", detail.to_s.downcase)
                  in .raw?, .string?, .unknown?
                    raise Crig::Completion::CompletionError.new("Unsupported document type: #{image.data.kind}")
                  end
                in .document?
                  document = user_content.document || raise Crig::Completion::CompletionError.new("Missing document content")
                  case document.data.kind
                  in .base64?, .string?
                    text = document.data.string_value || raise Crig::Completion::CompletionError.new("Document text is missing")
                    other_content << UserContent.text(text)
                  in .url?, .raw?, .unknown?
                    raise Crig::Completion::CompletionError.new("Documents must be base64 or a string")
                  end
                in .audio?
                  audio = user_content.audio || raise Crig::Completion::CompletionError.new("Missing audio content")
                  case audio.data.kind
                  in .base64?
                    data = audio.data.string_value || raise Crig::Completion::CompletionError.new("OpenAI audio data is missing")
                    other_content << UserContent.audio(
                      data,
                      Crig::Completion::MimeType.audio_to_mime_type(audio.media_type || Crig::Completion::AudioMediaType::MP3).sub("audio/", ""),
                    )
                  in .url?, .raw?, .unknown?, .string?
                    raise Crig::Completion::CompletionError.new("URLs are not supported for audio")
                  end
                in .tool_result?
                  tool_result = user_content.tool_result || raise Crig::Completion::CompletionError.new("Missing tool result content")
                  text = tool_result.content.to_a.map(&.text).join('\n')
                  content_value = ToolResultContentValue.from_string(text, tool_result_array_content)
                  tool_results << self.tool_result(tool_result.id, content_value)
                in .video?
                  raise Crig::Completion::CompletionError.new("Video is in unsupported format")
                end
              end

              return tool_results unless tool_results.empty?

              content = Crig::OneOrMany(UserContent).many(other_content)
              [user(content)]
            in .assistant?
              text_content = [] of AssistantContent
              tool_calls = [] of ToolCall

              message.content.each do |entry|
                next unless assistant_content = entry.as?(Crig::Completion::AssistantContent)
                case assistant_content.kind
                in .text?
                  text = assistant_content.text || raise Crig::Completion::CompletionError.new("Missing assistant text content")
                  text_content << AssistantContent.text(text.text)
                in .tool_call?
                  tool_call = assistant_content.tool_call || raise Crig::Completion::CompletionError.new("Missing assistant tool call content")
                  tool_calls << ToolCall.new(
                    tool_call.id,
                    Function.new(tool_call.function.name, tool_call.function.arguments),
                  )
                in .reasoning?
                  # Chat Completions drops assistant reasoning history, matching upstream.
                in .image?
                  raise Crig::Completion::CompletionError.new("The OpenAI Completions API doesn't support image content in assistant messages!")
                end
              end

              return [] of self if text_content.empty? && tool_calls.empty?
              [assistant(text_content, tool_calls)]
            end
          end

          # ameba:enable Metrics/CyclomaticComplexity

          def to_core_message : Crig::Completion::Message
            case @kind
            in .user?
              user_content = (@user_content || raise Crig::Completion::CompletionError.new("Response did not contain a valid user message")).map do |content|
                case content.kind
                in .text?
                  Crig::Completion::UserContent.text(content.text || "")
                in .image?
                  image = content.image_url || raise Crig::Completion::CompletionError.new("Missing OpenAI image content")
                  detail = Crig::Completion::ImageDetail.parse?(image.detail.capitalize) || Crig::Completion::ImageDetail::Auto
                  Crig::Completion::UserContent.image_url(image.url, nil, detail)
                in .audio?
                  audio = content.input_audio || raise Crig::Completion::CompletionError.new("Missing OpenAI audio content")
                  media_type = Crig::Completion::AudioMediaType.parse?(audio.format.upcase) || Crig::Completion::AudioMediaType::MP3
                  Crig::Completion::UserContent.audio(audio.data, media_type)
                end
              end
              widened_content = user_content.map { |content| content.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent) }
              content_one_or_many = Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(widened_content)
              Crig::Completion::Message.new(Crig::Completion::Message::Role::User, content_one_or_many)
            in .assistant?
              content = [] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)
              @assistant_content.each do |entry|
                content << entry.to_completion_content
              end
              @tool_calls.each do |tool_call|
                content << Crig::Completion::AssistantContent.tool_call(
                  tool_call.id,
                  tool_call.function.name,
                  tool_call.function.arguments,
                )
              end
              content_one_or_many = Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(content)
              Crig::Completion::Message.new(Crig::Completion::Message::Role::Assistant, content_one_or_many)
            in .tool_result?
              text = (@tool_result_content || raise Crig::Completion::CompletionError.new("Missing OpenAI tool result content")).as_text
              Crig::Completion::Message.tool_result(@tool_call_id || "", text)
            in .system?
              text = (@system_content || raise Crig::Completion::CompletionError.new("Missing OpenAI system content")).first.text
              Crig::Completion::Message.user(text)
            end
          end

          # ameba:disable Metrics/CyclomaticComplexity
          def to_json_value : JSON::Any
            case @kind
            in .system?
              OpenAI.build_json_any do |json|
                json.object do
                  json.field "role", "system"
                  json.field "content" do
                    content = @system_content || raise Crig::Completion::CompletionError.new("Missing OpenAI system content")
                    if content.size == 1
                      content.first.to_json(json)
                    else
                      json.array { content.each(&.to_json(json)) }
                    end
                  end
                  json.field "name", @name unless @name.nil?
                end
              end
            in .user?
              OpenAI.build_json_any do |json|
                json.object do
                  json.field "role", "user"
                  json.field "content" do
                    content = @user_content || raise Crig::Completion::CompletionError.new("Missing OpenAI user content")
                    if content.size == 1 && content.first.kind.text?
                      json.string(content.first.text || "")
                    else
                      json.array { content.each(&.to_json_value.to_json(json)) }
                    end
                  end
                  json.field "name", @name unless @name.nil?
                end
              end
            in .assistant?
              OpenAI.build_json_any do |json|
                json.object do
                  json.field "role", "assistant"
                  unless @assistant_content.empty?
                    json.field "content" do
                      json.array { @assistant_content.each(&.to_json_value.to_json(json)) }
                    end
                  end
                  json.field "refusal", @refusal unless @refusal.nil?
                  if audio = @audio
                    json.field "audio" { audio.to_json(json) }
                  end
                  json.field "name", @name unless @name.nil?
                  unless @tool_calls.empty?
                    json.field "tool_calls" do
                      json.array { @tool_calls.each(&.to_json_value.to_json(json)) }
                    end
                  end
                end
              end
            in .tool_result?
              OpenAI.build_json_any do |json|
                json.object do
                  json.field "role", "tool"
                  json.field "tool_call_id", @tool_call_id
                  json.field "content" do
                    (@tool_result_content || raise Crig::Completion::CompletionError.new("Missing OpenAI tool result content")).to_json_value.to_json(json)
                  end
                end
              end
            end
          end

          # ameba:enable Metrics/CyclomaticComplexity

          private def self.parse_system_content(value : JSON::Any) : Crig::OneOrMany(SystemContent)
            if text = value.as_s?
              Crig::OneOrMany(SystemContent).one(SystemContent.from_string(text))
            else
              Crig::OneOrMany(SystemContent).many(value.as_a.map { |entry| SystemContent.from_json(entry.to_json) })
            end
          end

          private def self.parse_user_content(value : JSON::Any) : Crig::OneOrMany(UserContent)
            if text = value.as_s?
              Crig::OneOrMany(UserContent).one(UserContent.from_string(text))
            else
              Crig::OneOrMany(UserContent).many(value.as_a.map { |entry| parse_user_content_entry(entry) })
            end
          end

          private def self.parse_user_content_entry(value : JSON::Any) : UserContent
            hash = value.as_h
            case hash["type"].as_s
            when "text"
              UserContent.text(hash["text"].as_s)
            when "image_url"
              image = hash["image_url"]
              UserContent.new(UserContent::Kind::Image, image_url: ImageUrl.from_json(image.to_json))
            when "input_audio"
              audio = hash["input_audio"]
              UserContent.new(UserContent::Kind::Audio, input_audio: InputAudio.from_json(audio.to_json))
            else
              raise Crig::Completion::CompletionError.new("Unsupported OpenAI user content type: #{hash["type"].as_s}")
            end
          end

          private def self.parse_assistant_content(value : JSON::Any?) : Array(AssistantContent)
            return [] of AssistantContent unless value
            return [] of AssistantContent if value.raw.nil?
            if text = value.as_s?
              [AssistantContent.text(text)]
            else
              value.as_a.map do |entry|
                hash = entry.as_h
                case hash["type"].as_s
                when "text"
                  AssistantContent.text(hash["text"].as_s)
                when "refusal"
                  AssistantContent.refusal(hash["refusal"].as_s)
                else
                  raise Crig::Completion::CompletionError.new("Unsupported OpenAI assistant content type: #{hash["type"].as_s}")
                end
              end
            end
          end

          private def self.parse_tool_call(value : JSON::Any) : ToolCall
            hash = value.as_h
            function = hash["function"]
            ToolCall.new(
              hash["id"].as_s,
              Function.new(
                function["name"].as_s,
                parse_json_or_string(function["arguments"].as_s),
              ),
            )
          end

          private def self.parse_tool_result_content(value : JSON::Any) : ToolResultContentValue
            if string = value.as_s?
              ToolResultContentValue.from_string(string)
            else
              ToolResultContentValue.new(
                ToolResultContentValue::Kind::Array,
                array_value: value.as_a.map { |entry| ToolResultContent.from_json(entry.to_json) },
              )
            end
          end

          private def self.parse_json_or_string(value : String) : JSON::Any
            JSON.parse(value)
          rescue
            JSON::Any.new(value)
          end
        end

        struct Choice
          include JSON::Serializable

          getter index : Int32
          @[JSON::Field(ignore: true)]
          getter message : Message
          getter logprobs : JSON::Any?
          @[JSON::Field(key: "finish_reason")]
          getter finish_reason : String

          def initialize(@index : Int32, @message : Message, @logprobs : JSON::Any? = nil, @finish_reason : String = "stop")
          end

          def self.from_json_value(value : JSON::Any) : self
            hash = value.as_h
            new(
              hash["index"].as_i,
              Message.from_json_value(hash["message"]),
              hash["logprobs"]?,
              hash["finish_reason"].as_s,
            )
          end
        end

        struct CompletionResponse
          include JSON::Serializable

          getter id : String
          getter object : String
          getter created : Int64
          getter model : String
          @[JSON::Field(key: "system_fingerprint")]
          getter system_fingerprint : String?
          @[JSON::Field(ignore: true)]
          getter choices : Array(Choice)
          getter usage : OpenAIUsage?

          def initialize(
            @id : String,
            @object : String,
            @created : Int64,
            @model : String,
            @choices : Array(Choice),
            @usage : OpenAIUsage? = nil,
            @system_fingerprint : String? = nil,
          )
          end

          def self.from_json_value(value : JSON::Any) : self
            hash = value.as_h
            new(
              hash["id"].as_s,
              hash["object"].as_s,
              hash["created"].as_i64,
              hash["model"].as_s,
              hash["choices"].as_a.map { |choice| Choice.from_json_value(choice) },
              hash["usage"]?.try { |usage| OpenAIUsage.from_json(usage.to_json) },
              hash["system_fingerprint"]?.try(&.as_s?),
            )
          end

          def to_completion_response(raw_response : JSON::Any) : Crig::Completion::CompletionResponse(JSON::Any)
            choice = @choices.first? || raise Crig::Completion::CompletionError.new("Response contained no choices")
            message = choice.message
            unless message.kind.assistant?
              raise Crig::Completion::CompletionError.new("Response did not contain a valid message or tool call")
            end

            content = [] of Crig::Completion::AssistantContent
            message.assistant_content.each do |entry|
              text = case entry.kind
                     in .text?
                       entry.text
                     in .refusal?
                       entry.text
                     end
              content << Crig::Completion::AssistantContent.text(text) unless text.to_s.empty?
            end
            message.tool_calls.each do |tool_call|
              content << Crig::Completion::AssistantContent.tool_call(
                tool_call.id,
                tool_call.function.name,
                tool_call.function.arguments,
              )
            end

            if content.empty?
              raise Crig::Completion::CompletionError.new("Response contained no message or tool call (empty)")
            end

            Crig::Completion::CompletionResponse(JSON::Any).new(
              Crig::OneOrMany(Crig::Completion::AssistantContent).many(content),
              @usage.try(&.to_crig_usage) || Crig::Completion::Usage.new,
              raw_response,
              @id,
            )
          end
        end

        struct OpenAIRequestParams
          getter model : String
          getter request : Crig::Completion::Request::CompletionRequest
          getter? strict_tools : Bool
          getter? tool_result_array_content : Bool

          def initialize(
            @model : String,
            @request : Crig::Completion::Request::CompletionRequest,
            @strict_tools : Bool = false,
            @tool_result_array_content : Bool = false,
          )
          end
        end

        struct CompletionRequest
          getter model : String
          getter messages : Array(Message)
          getter tools : Array(ToolDefinition)
          getter tool_choice : ToolChoice?
          getter temperature : Float64?
          getter max_tokens : Int64?
          getter additional_params : JSON::Any?

          def initialize(
            @model : String,
            @messages : Array(Message),
            @tools : Array(ToolDefinition) = [] of ToolDefinition,
            @tool_choice : ToolChoice? = nil,
            @temperature : Float64? = nil,
            @max_tokens : Int64? = nil,
            @additional_params : JSON::Any? = nil,
          )
          end

          def self.from_openai_request_params(params : OpenAIRequestParams) : self
            request = params.request
            partial_history = [] of Crig::Completion::Message
            if docs = request.normalized_documents
              partial_history << docs
            end
            partial_history.concat(request.chat_history.to_a)

            full_history = [] of Message
            if preamble = request.preamble
              full_history << Message.system(preamble)
            end

            partial_history.each do |message|
              converted = Message.from_core_message(message, params.tool_result_array_content?)
              converted.each { |item| full_history << item }
            end

            raise Crig::Completion::CompletionError.new("OpenAI Chat Completions request has no provider-compatible messages after conversion") if full_history.empty?

            tool_choice = request.tool_choice.try do |choice|
              case choice.kind
              in .auto?
                ToolChoice::Auto
              in .none?
                ToolChoice::None
              in .required?
                ToolChoice::Required
              in .specific?
                raise Crig::Completion::CompletionError.new("Provider doesn't support only using specific tools")
              end
            end

            tools = request.tools.map do |tool|
              definition = ToolDefinition.from_tool(tool)
              params.strict_tools? ? definition.with_strict : definition
            end

            additional_params = request.additional_params
            if output_schema = request.output_schema
              schema = OpenAI.sanitize_schema(output_schema)
              response_format = OpenAI.build_json_any do |json|
                json.object do
                  json.field "response_format" do
                    json.object do
                      json.field "type", "json_schema"
                      json.field "json_schema" do
                        json.object do
                          json.field "name", request.output_schema_name || "response_schema"
                          json.field "strict", true
                          json.field "schema" do
                            schema.to_json(json)
                          end
                        end
                      end
                    end
                  end
                end
              end
              additional_params = if existing = additional_params
                                    JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(existing.as_h, response_format.as_h).to_json)
                                  else
                                    response_format
                                  end
            end

            new(
              request.model || params.model,
              full_history,
              tools,
              tool_choice,
              request.temperature,
              request.max_tokens.try(&.to_i64),
              additional_params,
            )
          end

          def to_json_value : JSON::Any
            payload = OpenAI.build_json_any do |json|
              json.object do
                json.field "model", @model
                json.field "messages" do
                  json.array do
                    @messages.each(&.to_json_value.to_json(json))
                  end
                end
                unless @tools.empty?
                  json.field "tools" do
                    json.array do
                      @tools.each(&.to_json_value.to_json(json))
                    end
                  end
                end
                if tool_choice = @tool_choice
                  json.field "tool_choice", tool_choice.to_wire
                end
                json.field "temperature", @temperature unless @temperature.nil?
                json.field "max_tokens", @max_tokens unless @max_tokens.nil?
              end
            end
            if additional_params = @additional_params
              JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, additional_params.as_h).to_json)
            else
              payload
            end
          end
        end
      end

      module Chat
        module Streaming
          struct Function
            include JSON::Serializable

            getter name : String?
            getter arguments : String?
          end

          struct ToolCall
            include JSON::Serializable

            getter index : Int32
            getter id : String?
            getter function : Function
          end

          struct Delta
            include JSON::Serializable

            getter content : String?
            @[JSON::Field(key: "reasoning_content")]
            getter reasoning_content : String?
            @[JSON::Field(ignore: true)]
            getter tool_calls : Array(ToolCall)

            def initialize(
              @content : String? = nil,
              @reasoning_content : String? = nil,
              @tool_calls : Array(ToolCall) = [] of ToolCall,
            )
            end

            def self.from_json_value(value : JSON::Any) : self
              hash = value.as_h
              new(
                hash["content"]?.try(&.as_s?),
                hash["reasoning_content"]?.try(&.as_s?),
                hash["tool_calls"]?.try(&.as_a?).try(&.map { |entry| ToolCall.from_json(entry.to_json) }) || [] of ToolCall,
              )
            end
          end

          struct FinishReason
            enum Kind
              ToolCalls
              Stop
              ContentFilter
              Length
              Other
            end

            getter kind : Kind
            getter value : String

            def initialize(@kind : Kind, @value : String)
            end

            def self.from_string(value : String) : self
              case value
              when "tool_calls"
                new(Kind::ToolCalls, value)
              when "stop"
                new(Kind::Stop, value)
              when "content_filter"
                new(Kind::ContentFilter, value)
              when "length"
                new(Kind::Length, value)
              else
                new(Kind::Other, value)
              end
            end

            def tool_calls? : Bool
              @kind.tool_calls?
            end
          end

          struct Choice
            getter delta : Delta
            getter finish_reason : FinishReason?

            def initialize(@delta : Delta, @finish_reason : FinishReason? = nil)
            end

            def self.from_json_value(value : JSON::Any) : self
              hash = value.as_h
              new(
                Delta.from_json_value(hash["delta"]),
                hash["finish_reason"]?.try(&.as_s?).try { |reason| FinishReason.from_string(reason) },
              )
            end
          end

          struct CompletionChunk
            getter choices : Array(Choice)
            getter usage : OpenAIUsage?

            def initialize(@choices : Array(Choice), @usage : OpenAIUsage? = nil)
            end

            def self.from_json_value(value : JSON::Any) : self
              hash = value.as_h
              new(
                hash["choices"]?.try(&.as_a?).try(&.map { |entry| Choice.from_json_value(entry) }) || [] of Choice,
                hash["usage"]?.try(&.as_h?).try { |usage| OpenAIUsage.from_json(usage.to_json) },
              )
            end
          end

          struct CompletionResponse
            include JSON::Serializable
            include Crig::Completion::GetTokenUsage

            getter usage : OpenAIUsage

            def initialize(@usage : OpenAIUsage = OpenAIUsage.new)
            end

            def token_usage : Crig::Completion::Usage?
              @usage.to_crig_usage
            end
          end
        end
      end

      struct CompletionModel
        include Crig::Completion::CompletionModel

        getter client : CompletionsClient
        getter model : String
        getter? strict_tools : Bool
        getter? tool_result_array_content : Bool

        def initialize(
          @client : CompletionsClient,
          @model : String,
          @strict_tools : Bool = false,
          @tool_result_array_content : Bool = false,
        )
        end

        def self.with_model(client : CompletionsClient, model : String) : self
          new(client, model)
        end

        def with_model(model : String) : self
          self.class.new(@client, model, @strict_tools, @tool_result_array_content)
        end

        def with_strict_tools : self
          self.class.new(@client, @model, true, @tool_result_array_content)
        end

        def with_tool_result_array_content : self
          self.class.new(@client, @model, @strict_tools, true)
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          payload = build_request_payload(request)
          response = @client.post_json("/chat/completions", payload.to_json)
          text = response.body

          if response.status_code >= 400
            raise Crig::Completion::CompletionError.new(text)
          end

          body = JSON.parse(text)
          if error = body["error"]?
            raise Crig::Completion::CompletionError.new(error["message"].as_s)
          end

          parse_completion_response(body)
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = build_request_payload(request)
          payload = Crig::Providers::OpenAI.merge_json_hashes(
            payload,
            {
              "stream"         => JSON::Any.new(true),
              "stream_options" => JSON.parse(%({"include_usage":true})),
            }
          )
          response = @client.post_json(
            "/chat/completions",
            payload.to_json,
            {"Accept" => "text/event-stream"}
          )
          text = response.body

          if response.status_code >= 400
            raise Crig::Completion::CompletionError.new(text)
          end

          raw_choices = parse_streaming_choices(text)
          Crig::StreamingCompletionResponse(Crig::Client::FinalCompletionResponse).stream_raw_choices(raw_choices)
        end

        private def parse_completion_response(body : JSON::Any) : Crig::Completion::CompletionResponse(JSON::Any)
          Chat::CompletionResponse.from_json_value(body).to_completion_response(body)
        end

        # ameba:disable Metrics/CyclomaticComplexity
        private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse)
          tool_calls = {} of Int32 => {String, String, String}
          final_response = Chat::Streaming::CompletionResponse.new
          message_id : String? = nil

          text.each_line do |line|
            next unless line.starts_with?("data:")
            data = line.lchop("data:").strip
            next if data.empty? || data == "[DONE]"

            chunk_json = JSON.parse(data)
            if id = chunk_json["id"]?.try(&.as_s?)
              unless message_id
                message_id = id
                raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message_id(id)
              end
            end

            chunk = Chat::Streaming::CompletionChunk.from_json_value(chunk_json)
            if usage = chunk.usage
              final_response = Chat::Streaming::CompletionResponse.new(usage)
            end

            choice = chunk.choices.first?
            next unless choice
            delta = choice.delta

            if message = delta.content
              raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).message(message)
            end

            if reasoning = delta.reasoning_content
              raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).reasoning_delta(nil, reasoning)
            end

            delta.tool_calls.each do |tool_call|
              index = tool_call.index
              id = tool_call.id || tool_calls[index]?.try(&.[0]) || ""
              incoming_name = tool_call.function.name
              name = incoming_name || tool_calls[index]?.try(&.[1]) || ""
              arguments_delta = tool_call.function.arguments || ""
              existing_args = tool_calls[index]?.try(&.[2]) || ""
              combined_arguments = existing_args + arguments_delta
              tool_calls[index] = {id, name, combined_arguments}

              if incoming_name && !incoming_name.empty?
                raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).tool_call_delta(
                  id,
                  id.empty? ? index.to_s : id,
                  Crig::ToolCallDeltaContent.name(incoming_name),
                )
              end
              unless arguments_delta.empty?
                raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).tool_call_delta(
                  id,
                  id.empty? ? index.to_s : id,
                  Crig::ToolCallDeltaContent.delta(arguments_delta),
                )
              end
            end

            if choice.finish_reason.try(&.tool_calls?)
              tool_calls.keys.sort!.each do |index|
                next unless current_tool_call = tool_calls[index]?
                id, name, arguments = current_tool_call
                tool_calls.delete(index)
                raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).tool_call(
                  Crig::RawStreamingToolCall.new(
                    id,
                    name,
                    parse_json_or_string(arguments),
                    id.empty? ? index.to_s : id,
                  )
                )
              end
            end
          end

          tool_calls.keys.sort!.each do |index|
            id, name, arguments = tool_calls[index]
            raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).tool_call(
              Crig::RawStreamingToolCall.new(
                id,
                name,
                parse_json_or_string(arguments),
                id.empty? ? index.to_s : id,
              )
            )
          end

          raw_choices << Crig::RawStreamingChoice(Crig::Client::FinalCompletionResponse).final_response(
            Crig::Client::FinalCompletionResponse.new(final_response.token_usage)
          )
          raw_choices
        end

        # ameba:enable Metrics/CyclomaticComplexity

        private def build_request_payload(request : Crig::Completion::Request::CompletionRequest) : Hash(String, JSON::Any)
          Chat::CompletionRequest.from_openai_request_params(
            Chat::OpenAIRequestParams.new(@model, request, @strict_tools, @tool_result_array_content)
          ).to_json_value.as_h
        end

        private def parse_json_or_string(value : String) : JSON::Any
          JSON.parse(value)
        rescue
          JSON::Any.new(value)
        end

        private def parse_usage(value : JSON::Any?) : Crig::Completion::Usage
          return Crig::Completion::Usage.new unless value
          OpenAIUsage.from_json(value.to_json).to_crig_usage
        end
      end

      struct CompletionsClient
        include Crig::CompletionClient(Crig::Providers::OpenAI::CompletionModel)
      end
    end
  end
end
