module Crig
  module Providers
    module Cohere
      enum FinishReason
        MaxTokens
        StopSequence
        Complete
        Error
        ToolCall

        def self.from_wire(value : String) : self
          case value
          when "MAX_TOKENS"    then MaxTokens
          when "STOP_SEQUENCE" then StopSequence
          when "COMPLETE"      then Complete
          when "ERROR"         then Error
          when "TOOL_CALL"     then ToolCall
          else
            raise Crig::Completion::CompletionError.new("Unknown Cohere finish_reason: #{value}")
          end
        end

        def to_wire : String
          case self
          in .max_tokens?    then "MAX_TOKENS"
          in .stop_sequence? then "STOP_SEQUENCE"
          in .complete?      then "COMPLETE"
          in .error?         then "ERROR"
          in .tool_call?     then "TOOL_CALL"
          end
        end
      end

      struct Tokens
        include JSON::Serializable

        @[JSON::Field(key: "input_tokens")]
        getter input_tokens : Float64?
        @[JSON::Field(key: "output_tokens")]
        getter output_tokens : Float64?

        def initialize(@input_tokens : Float64? = nil, @output_tokens : Float64? = nil)
        end
      end

      struct BilledUnits
        include JSON::Serializable

        @[JSON::Field(key: "output_tokens")]
        getter output_tokens : Float64?
        getter classifications : Float64?
        @[JSON::Field(key: "search_units")]
        getter search_units : Float64?
        @[JSON::Field(key: "input_tokens")]
        getter input_tokens : Float64?

        def initialize(
          @output_tokens : Float64? = nil,
          @classifications : Float64? = nil,
          @search_units : Float64? = nil,
          @input_tokens : Float64? = nil,
        )
        end
      end

      struct Usage
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        @[JSON::Field(key: "billed_units")]
        getter billed_units : BilledUnits?
        getter tokens : Tokens?

        def initialize(@billed_units : BilledUnits? = nil, @tokens : Tokens? = nil)
        end

        def token_usage : Crig::Completion::Usage?
          usage = Crig::Completion::Usage.new
          if billed_units = @billed_units
            usage = Crig::Completion::Usage.new(
              input_tokens: billed_units.input_tokens.try(&.to_i64) || 0_i64,
              output_tokens: billed_units.output_tokens.try(&.to_i64) || 0_i64,
              total_tokens: (billed_units.input_tokens.try(&.to_i64) || 0_i64) + (billed_units.output_tokens.try(&.to_i64) || 0_i64),
            )
          end
          usage
        end

        def completion_usage : Crig::Completion::Usage
          if tokens = @tokens
            input_tokens = tokens.input_tokens.try(&.to_i64) || 0_i64
            output_tokens = tokens.output_tokens.try(&.to_i64) || 0_i64
            Crig::Completion::Usage.new(
              input_tokens: input_tokens,
              output_tokens: output_tokens,
              total_tokens: input_tokens + output_tokens,
            )
          else
            Crig::Completion::Usage.new
          end
        end
      end

      struct Document
        include JSON::Serializable

        getter id : String
        getter data : Hash(String, JSON::Any)

        def initialize(@id : String, @data : Hash(String, JSON::Any))
        end

        def self.from_core(document : Crig::Completion::Request::Document) : self
          data = {} of String => JSON::Any
          document.additional_props.each do |key, value|
            data[key] = JSON::Any.new(value)
          end
          data["text"] = JSON::Any.new(document.text)
          new(document.id, data)
        end
      end

      enum ToolType
        Function

        def self.from_wire(value : String?) : self?
          case value
          when nil        then nil
          when "function" then Function
          else
            raise Crig::Completion::CompletionError.new("Unknown Cohere tool type: #{value}")
          end
        end

        def to_wire : String
          "function"
        end
      end

      struct ToolCallFunction
        getter name : String
        getter arguments : JSON::Any

        def initialize(@name : String, @arguments : JSON::Any)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(hash["name"].as_s, JSON.parse(hash["arguments"].as_s))
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "name", @name
            json.field "arguments", @arguments.to_json
          end
        end
      end

      struct ToolCall
        getter id : String?
        getter type : ToolType?
        getter function : ToolCallFunction?

        def initialize(@id : String? = nil, @type : ToolType? = nil, @function : ToolCallFunction? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["id"]?.try(&.as_s?),
            ToolType.from_wire(hash["type"]?.try(&.as_s?)),
            hash["function"]?.try { |entry| ToolCallFunction.from_json_value(entry) },
          )
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "id", @id unless @id.nil?
            if type = @type
              json.field "type", type.to_wire
            end
            if function = @function
              json.field "function" { function.to_json(json) }
            end
          end
        end
      end

      struct Function
        getter name : String
        getter description : String?
        getter parameters : JSON::Any

        def initialize(@name : String, @parameters : JSON::Any, @description : String? = nil)
        end

        def self.from_core(tool : Crig::Completion::ToolDefinition) : self
          new(tool.name, tool.parameters, tool.description)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "name", @name
            json.field "description", @description unless @description.nil?
            json.field "parameters" { @parameters.to_json(json) }
          end
        end
      end

      struct Tool
        getter type : ToolType
        getter function : Function

        def initialize(@type : ToolType, @function : Function)
        end

        def self.from_core(tool : Crig::Completion::ToolDefinition) : self
          new(ToolType::Function, Function.from_core(tool))
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "type", @type.to_wire
            json.field "function" { @function.to_json(json) }
          end
        end
      end

      struct ImageUrl
        include JSON::Serializable

        getter url : String

        def initialize(@url : String)
        end
      end

      struct UserContent
        enum Kind
          Text
          ImageUrl
        end

        getter kind : Kind
        getter text : String?
        getter image_url : ImageUrl?

        def initialize(@kind : Kind, @text : String? = nil, @image_url : ImageUrl? = nil)
        end

        def self.text(text : String) : self
          new(Kind::Text, text: text)
        end

        def self.image_url(url : String) : self
          new(Kind::ImageUrl, image_url: ImageUrl.new(url))
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["type"].as_s
          when "text"
            text(hash["text"].as_s)
          when "image_url"
            image_url(hash["image_url"].as_h["url"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unknown Cohere user content type")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .text?
              json.field "type", "text"
              json.field "text", @text
            in .image_url?
              json.field "type", "image_url"
              image_url = @image_url || raise Crig::Completion::CompletionError.new("Missing Cohere image_url content")
              json.field "image_url" { image_url.to_json.to_json(json) }
            end
          end
        end
      end

      struct AssistantContent
        enum Kind
          Text
          Thinking
        end

        getter kind : Kind
        getter text : String?
        getter thinking : String?

        def initialize(@kind : Kind, @text : String? = nil, @thinking : String? = nil)
        end

        def self.text(text : String) : self
          new(Kind::Text, text: text)
        end

        def self.thinking(thinking : String) : self
          new(Kind::Thinking, thinking: thinking)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["type"].as_s
          when "text"
            text(hash["text"].as_s)
          when "thinking"
            thinking(hash["thinking"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unknown Cohere assistant content type")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .text?
              json.field "type", "text"
              json.field "text", @text
            in .thinking?
              json.field "type", "thinking"
              json.field "thinking", @thinking
            end
          end
        end
      end

      struct CitationType
        getter value : String

        def initialize(@value : String)
        end

        def self.from_wire(value : String?) : self?
          value ? new(value) : nil
        end
      end

      struct Source
        enum Kind
          Document
          Tool
        end

        getter kind : Kind
        getter id : String?
        getter document : Hash(String, JSON::Any)?
        getter tool_output : Hash(String, JSON::Any)?

        def initialize(@kind : Kind, @id : String? = nil, @document : Hash(String, JSON::Any)? = nil, @tool_output : Hash(String, JSON::Any)? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["type"].as_s
          when "document"
            new(Kind::Document, hash["id"]?.try(&.as_s?), hash["document"]?.try(&.as_h))
          when "tool"
            new(Kind::Tool, hash["id"]?.try(&.as_s?), nil, hash["tool_output"]?.try(&.as_h))
          else
            raise Crig::Completion::CompletionError.new("Unknown Cohere citation source type")
          end
        end
      end

      struct Citation
        getter start : Int32?
        getter end_ : Int32?
        getter text : String?
        getter citation_type : CitationType?
        getter sources : Array(Source)

        def initialize(
          @start : Int32? = nil,
          @end_ : Int32? = nil,
          @text : String? = nil,
          @citation_type : CitationType? = nil,
          @sources : Array(Source) = [] of Source,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["start"]?.try(&.as_i),
            hash["end"]?.try(&.as_i),
            hash["text"]?.try(&.as_s?),
            CitationType.from_wire(hash["type"]?.try(&.as_s?)),
            hash["sources"]?.try(&.as_a.map { |entry| Source.from_json_value(entry) }) || [] of Source,
          )
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "start", @start unless @start.nil?
            json.field "end", @end_ unless @end_.nil?
            json.field "text", @text unless @text.nil?
            if citation_type = @citation_type
              json.field "type", citation_type.value
            end
            unless @sources.empty?
              json.field "sources" do
                json.array { @sources.each(&.to_json(json)) }
              end
            end
          end
        end
      end

      struct Source
        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .document?
              json.field "type", "document"
              json.field "id", @id unless @id.nil?
              if document = @document
                json.field "document" { document.to_json.to_json(json) }
              end
            in .tool?
              json.field "type", "tool"
              json.field "id", @id unless @id.nil?
              if tool_output = @tool_output
                json.field "tool_output" { tool_output.to_json.to_json(json) }
              end
            end
          end
        end
      end

      struct ToolResultContent
        enum Kind
          Text
          Document
        end

        getter kind : Kind
        getter text : String?
        getter document : Document?

        def initialize(@kind : Kind, @text : String? = nil, @document : Document? = nil)
        end

        def self.text(text : String) : self
          new(Kind::Text, text: text)
        end

        def self.document(document : Document) : self
          new(Kind::Document, document: document)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          if text = hash["text"]?.try(&.as_s?)
            self.text(text)
          elsif document = hash["document"]?
            self.document(Document.from_json(document.to_json))
          else
            raise Crig::Completion::CompletionError.new("Unknown Cohere tool result content")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .text?
              json.field "text", @text
            in .document?
              document = @document || raise Crig::Completion::CompletionError.new("Missing Cohere tool result document")
              json.field "document" { document.to_json.to_json(json) }
            end
          end
        end
      end

      struct Message
        enum Kind
          User
          Assistant
          Tool
          System
        end

        getter kind : Kind
        getter user_content : Crig::OneOrMany(UserContent)?
        getter assistant_content : Array(AssistantContent)
        getter citations : Array(Citation)
        getter tool_calls : Array(ToolCall)
        getter tool_plan : String?
        getter tool_result_content : Crig::OneOrMany(ToolResultContent)?
        getter tool_call_id : String?
        getter system_content : String?

        def initialize(
          @kind : Kind,
          @user_content : Crig::OneOrMany(UserContent)? = nil,
          @assistant_content : Array(AssistantContent) = [] of AssistantContent,
          @citations : Array(Citation) = [] of Citation,
          @tool_calls : Array(ToolCall) = [] of ToolCall,
          @tool_plan : String? = nil,
          @tool_result_content : Crig::OneOrMany(ToolResultContent)? = nil,
          @tool_call_id : String? = nil,
          @system_content : String? = nil,
        )
        end

        def self.user(content : Crig::OneOrMany(UserContent)) : self
          new(Kind::User, user_content: content)
        end

        def self.assistant(
          content : Array(AssistantContent),
          citations : Array(Citation) = [] of Citation,
          tool_calls : Array(ToolCall) = [] of ToolCall,
          tool_plan : String? = nil,
        ) : self
          new(Kind::Assistant, assistant_content: content, citations: citations, tool_calls: tool_calls, tool_plan: tool_plan)
        end

        def self.tool(content : Crig::OneOrMany(ToolResultContent), tool_call_id : String) : self
          new(Kind::Tool, tool_result_content: content, tool_call_id: tool_call_id)
        end

        def self.system(content : String) : self
          new(Kind::System, system_content: content)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["role"].as_s
          when "user"
            raw_content = hash["content"]
            content = if raw_content.raw.is_a?(Array)
                        Crig::OneOrMany(UserContent).many(raw_content.as_a.map { |entry| UserContent.from_json_value(entry) })
                      else
                        Crig::OneOrMany(UserContent).one(UserContent.from_json_value(raw_content))
                      end
            user(content)
          when "assistant"
            assistant(
              hash["content"]?.try(&.as_a.map { |entry| AssistantContent.from_json_value(entry) }) || [] of AssistantContent,
              hash["citations"]?.try(&.as_a.map { |entry| Citation.from_json_value(entry) }) || [] of Citation,
              hash["tool_calls"]?.try(&.as_a.map { |entry| ToolCall.from_json_value(entry) }) || [] of ToolCall,
              hash["tool_plan"]?.try(&.as_s?),
            )
          when "tool"
            raw_content = hash["content"]
            content = if raw_content.raw.is_a?(Array)
                        Crig::OneOrMany(ToolResultContent).many(raw_content.as_a.map { |entry| ToolResultContent.from_json_value(entry) })
                      else
                        Crig::OneOrMany(ToolResultContent).one(ToolResultContent.from_json_value(raw_content))
                      end
            tool(content, hash["tool_call_id"].as_s)
          when "system"
            system(hash["content"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unknown Cohere message role")
          end
        end

        def self.from_core_message(message : Crig::Completion::Message) : Array(self)
          case message.role
          in .user?
            message.content.to_a.map { |entry| from_core_user_or_tool_content(entry) }
          in .assistant?
            [from_core_assistant_message(message)]
          end
        end

        def to_core_message : Crig::Completion::Message
          case @kind
          in .user?
            to_core_user_message
          in .assistant?
            to_core_assistant_message
          in .tool?
            to_core_tool_message
          in .system?
            Crig::Completion::Message.user(@system_content || "")
          end
        end

        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              case @kind
              in .user?
                user_content = @user_content || raise Crig::Completion::CompletionError.new("Missing Cohere user content")
                json.field "role", "user"
                json.field "content" do
                  json.array { user_content.each(&.to_json(json)) }
                end
              in .assistant?
                json.field "role", "assistant"
                json.field "content" do
                  json.array { @assistant_content.each(&.to_json(json)) }
                end
                unless @citations.empty?
                  json.field "citations" { json.array { @citations.each(&.to_json(json)) } }
                end
                unless @tool_calls.empty?
                  json.field "tool_calls" { json.array { @tool_calls.each(&.to_json(json)) } }
                end
                json.field "tool_plan", @tool_plan unless @tool_plan.nil?
              in .tool?
                tool_result_content = @tool_result_content || raise Crig::Completion::CompletionError.new("Missing Cohere tool result content")
                json.field "role", "tool"
                json.field "content" do
                  json.array { tool_result_content.each(&.to_json(json)) }
                end
                json.field "tool_call_id", @tool_call_id
              in .system?
                json.field "role", "system"
                json.field "content", @system_content
              end
            end
          end
        end

        private def self.from_core_user_or_tool_content(entry : Crig::Completion::UserContent | Crig::Completion::AssistantContent) : Message
          user_content = entry.as?(Crig::Completion::UserContent) || raise Crig::Completion::MessageError.new("Only user content is supported by Cohere")
          case user_content.kind
          in .text?
            text = user_content.text.try(&.text) || raise Crig::Completion::MessageError.new("Missing text user content")
            Message.user(Crig::OneOrMany(UserContent).one(UserContent.text(text)))
          in .tool_result?
            tool_result = user_content.tool_result || raise Crig::Completion::MessageError.new("Missing tool result content")
            converted = tool_result.content.to_a.map do |tool_content|
              case tool_content.kind
              in .text?
                text = tool_content.text.try(&.text) || raise Crig::Completion::MessageError.new("Missing text tool result content")
                ToolResultContent.text(text)
              in .image?
                raise Crig::Completion::MessageError.new("Only text tool result content is supported by Cohere")
              end
            end
            Message.tool(Crig::OneOrMany(ToolResultContent).many(converted), tool_result.id)
          in .image?, .audio?, .video?, .document?
            raise Crig::Completion::MessageError.new("Only text content is supported by Cohere")
          end
        end

        private def self.from_core_assistant_message(message : Crig::Completion::Message) : Message
          text_content = [] of AssistantContent
          tool_calls = [] of ToolCall
          message.content.each do |entry|
            assistant_content = entry.as?(Crig::Completion::AssistantContent) || raise Crig::Completion::MessageError.new("Only assistant content is supported by Cohere")
            case assistant_content.kind
            in .text?
              text = assistant_content.text.try(&.text) || raise Crig::Completion::MessageError.new("Missing assistant text content")
              text_content << AssistantContent.text(text)
            in .tool_call?
              tool_call = assistant_content.tool_call || raise Crig::Completion::MessageError.new("Missing assistant tool call")
              tool_calls << ToolCall.new(
                tool_call.id,
                ToolType::Function,
                ToolCallFunction.new(tool_call.function.name, tool_call.function.arguments),
              )
            in .reasoning?
              reasoning = assistant_content.reasoning || raise Crig::Completion::MessageError.new("Missing assistant reasoning content")
              text_content << AssistantContent.thinking(reasoning.display_text)
            in .image?
              raise Crig::Completion::MessageError.new("Cohere currently doesn't support images.")
            end
          end
          Message.assistant(text_content, tool_calls: tool_calls)
        end

        private def to_core_user_message : Crig::Completion::Message
          user_content = @user_content || raise Crig::Completion::CompletionError.new("Missing Cohere user content")
          converted = user_content.to_a.map do |item|
            case item.kind
            in .text?
              Crig::Completion::UserContent.text(item.text || "")
            in .image_url?
              image_url = item.image_url || raise Crig::Completion::CompletionError.new("Missing Cohere image URL")
              Crig::Completion::UserContent.image_url(image_url.url)
            end.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
          end
          Crig::Completion::Message.new(
            Crig::Completion::Message::Role::User,
            Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(converted),
          )
        end

        private def to_core_assistant_message : Crig::Completion::Message
          converted = @assistant_content.map do |item|
            case item.kind
            in .text?
              Crig::Completion::AssistantContent.text(item.text || "")
            in .thinking?
              Crig::Completion::AssistantContent.new(
                Crig::Completion::AssistantContent::Kind::Reasoning,
                reasoning: Crig::Completion::Reasoning.new(item.thinking || ""),
              )
            end
          end
          @tool_calls.each do |tool_call|
            next unless function = tool_call.function
            converted << Crig::Completion::AssistantContent.tool_call(
              tool_call.id || function.name,
              function.name,
              function.arguments,
            )
          end

          Crig::Completion::Message.new(
            Crig::Completion::Message::Role::Assistant,
            Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
              converted.map(&.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent))
            ),
          )
        end

        private def to_core_tool_message : Crig::Completion::Message
          tool_result_content = @tool_result_content || raise Crig::Completion::CompletionError.new("Missing Cohere tool result content")
          converted = tool_result_content.to_a.map do |item|
            case item.kind
            in .text?
              Crig::Completion::ToolResultContent.text(item.text || "")
            in .document?
              document = item.document || raise Crig::Completion::CompletionError.new("Missing Cohere tool result document")
              Crig::Completion::ToolResultContent.text(document.data.to_json)
            end
          end
          Crig::Completion::Message.new(
            Crig::Completion::Message::Role::User,
            Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
              Crig::Completion::UserContent.tool_result(@tool_call_id || "", Crig::OneOrMany(Crig::Completion::ToolResultContent).many(converted))
            ),
          )
        end
      end

      struct CompletionResponse
        getter id : String
        getter finish_reason : FinishReason
        getter raw_message : Message
        getter usage : Usage?

        def initialize(@id : String, @finish_reason : FinishReason, @raw_message : Message, @usage : Usage? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["id"].as_s,
            FinishReason.from_wire(hash["finish_reason"].as_s),
            Message.from_json_value(hash["message"]),
            hash["usage"]?.try { |entry| Usage.from_json(entry.to_json) },
          )
        end

        def message : {Array(AssistantContent), Array(Citation), Array(ToolCall)}
          @raw_message.kind.assistant? || raise "Completion responses will only return an assistant message"
          {@raw_message.assistant_content, @raw_message.citations, @raw_message.tool_calls}
        end

        def to_crig_response : Crig::Completion::CompletionResponse(self)
          content, _, tool_calls = message

          model_response = if !tool_calls.empty?
                             Crig::OneOrMany(Crig::Completion::AssistantContent).many(
                               tool_calls.compact_map do |tool_call|
                                 function = tool_call.function
                                 next unless function
                                 id = tool_call.id || function.name
                                 Crig::Completion::AssistantContent.tool_call(id, function.name, function.arguments)
                               end
                             )
                           else
                             Crig::OneOrMany(Crig::Completion::AssistantContent).many(
                               content.map do |item|
                                 case item.kind
                                 in .text?
                                   Crig::Completion::AssistantContent.text(item.text || "")
                                 in .thinking?
                                   Crig::Completion::AssistantContent.new(
                                     Crig::Completion::AssistantContent::Kind::Reasoning,
                                     reasoning: Crig::Completion::Reasoning.new(item.thinking || "")
                                   )
                                 end
                               end
                             )
                           end

          choice = model_response || raise Crig::Completion::CompletionError.new("Response contained no message or tool call (empty)")
          Crig::Completion::CompletionResponse(self).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).many(choice.to_a),
            @usage.try(&.completion_usage) || Crig::Completion::Usage.new,
            self,
          )
        end
      end

      struct CohereCompletionRequest
        getter model : String
        getter messages : Array(Message)
        getter documents : Array(Crig::Completion::Request::Document)
        getter temperature : Float64?
        getter tools : Array(Tool)
        getter tool_choice : Crig::Completion::ToolChoice?
        getter additional_params : JSON::Any?

        def initialize(
          @model : String,
          @messages : Array(Message),
          @documents : Array(Crig::Completion::Request::Document),
          @temperature : Float64? = nil,
          @tools : Array(Tool) = [] of Tool,
          @tool_choice : Crig::Completion::ToolChoice? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def self.from_request(default_model : String, req : Crig::Completion::Request::CompletionRequest) : self
          if req.output_schema
            # Rust only warns here; Crystal keeps the request but does not enforce schema conversion.
          end

          model = req.model || default_model
          partial_history = [] of Crig::Completion::Message
          if docs = req.normalized_documents
            partial_history << docs
          end
          partial_history.concat(req.chat_history.to_a)

          full_history = [] of Message
          if preamble = req.preamble
            full_history << Message.system(preamble)
          end

          partial_history.each do |message|
            full_history.concat(Message.from_core_message(message))
          end

          if req.tool_choice.try(&.kind.auto?)
            raise Crig::Completion::CompletionError.new(%("auto" is not an allowed tool_choice value in the Cohere API))
          end

          new(
            model,
            full_history,
            req.documents,
            req.temperature,
            req.tools.map { |tool| Tool.from_core(tool) },
            req.tool_choice,
            req.additional_params,
          )
        end

        def to_json_value : JSON::Any
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "messages" do
                json.array { @messages.each(&.to_json_value.to_json(json)) }
              end
              json.field "documents" do
                json.array { @documents.each { |document| Document.from_core(document).to_json.to_json(json) } }
              end
              json.field "temperature", @temperature unless @temperature.nil?
              unless @tools.empty?
                json.field "tools" do
                  json.array { @tools.each(&.to_json(json)) }
                end
              end
              if tool_choice = @tool_choice
                json.field "tool_choice" { tool_choice.to_json(json) }
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

      struct CompletionModel
        include Crig::Completion::CompletionModel

        getter client : Client
        getter model : String

        def initialize(@client : Client, @model : String)
        end

        def self.make(client : Client, model : String) : self
          new(client, model)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.current
          span.set_attribute(Crig::Telemetry::GEN_AI_OPERATION_NAME, "chat")
          span.set_attribute(Crig::Telemetry::GEN_AI_PROVIDER_NAME, "cohere")
          span.set_attribute(Crig::Telemetry::GEN_AI_REQUEST_MODEL, @model)
          if preamble = request.preamble
            span.set_attribute(Crig::Telemetry::GEN_AI_SYSTEM_INSTRUCTIONS, preamble)
          end

          payload = CohereCompletionRequest.from_request(@model, request).to_json_value
          response = @client.post_json("/v2/chat", payload.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          body = ApiResponse(CompletionResponse).from_json_value(parsed) { |value| CompletionResponse.from_json_value(value) }
          if error = body.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          response_body = body.ok || raise Crig::Completion::CompletionError.new("Cohere response did not include a success payload")
          result = response_body.to_crig_response
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          Streaming::StreamingCompletionResponseParser.new(self).stream(request)
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Cohere::CompletionModel)
      end
    end
  end
end
