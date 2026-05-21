module Crig
  module Providers
    module Mistral
      CODESTRAL       = "codestral-latest"
      MISTRAL_LARGE   = "mistral-large-latest"
      PIXTRAL_LARGE   = "pixtral-large-latest"
      MISTRAL_SABA    = "mistral-saba-latest"
      MINISTRAL_3B    = "ministral-3b-latest"
      MINISTRAL_8B    = "ministral-8b-latest"
      MISTRAL_SMALL   = "mistral-small-latest"
      PIXTRAL_SMALL   = "pixtral-12b-2409"
      MISTRAL_NEMO    = "open-mistral-nemo"
      CODESTRAL_MAMBA = "open-codestral-mamba"

      struct AssistantContent
        include JSON::Serializable

        getter text : String

        def initialize(@text : String)
        end

        def self.from_string(text : String) : self
          new(text)
        end
      end

      enum ToolResultContentType
        Text

        def to_wire : String
          "text"
        end
      end

      struct ToolResultContent
        getter type : ToolResultContentType
        getter text : String

        def initialize(@text : String, @type : ToolResultContentType = ToolResultContentType::Text)
        end

        def self.from_string(text : String) : self
          new(text)
        end
      end

      enum UserContent
        Text
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

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "name", @name
            json.field "arguments", @arguments.to_json
          end
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          raw_arguments = hash["arguments"]
          arguments = raw_arguments.as_s?.try { |text| JSON.parse(text) } || raw_arguments
          new(hash["name"].as_s, arguments)
        end
      end

      struct ToolCall
        getter id : String
        getter type : ToolType
        getter function : Function

        def initialize(@id : String, @function : Function, @type : ToolType = ToolType::Function)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(hash["id"].as_s, Function.from_json_value(hash["function"]))
        end

        def self.from_core(tool_call : Crig::Completion::ToolCall) : self
          new(tool_call.id, Function.new(tool_call.function.name, tool_call.function.arguments))
        end
      end

      struct ToolDefinition
        getter type : String
        getter function : Crig::Completion::ToolDefinition

        def initialize(@function : Crig::Completion::ToolDefinition, @type : String = "function")
        end

        def self.from_core(tool : Crig::Completion::ToolDefinition) : self
          new(tool)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "type", @type
            json.field "function" { @function.to_json(json) }
          end
        end
      end

      enum ToolChoice
        Auto
        None
        Any

        def self.from_core(value : Crig::Completion::ToolChoice) : self
          case value.kind
          in .auto?
            Auto
          in .none?
            None
          in .required?
            Any
          in .specific?
            raise Crig::Completion::CompletionError.new("Mistral doesn't support requiring specific tools to be called")
          end
        end
      end

      struct Message
        enum Kind
          User
          Assistant
          System
          Tool
        end

        getter kind : Kind
        getter content : String
        getter tool_calls : Array(ToolCall)
        getter? prefix : Bool
        getter name : String?
        getter tool_call_id : String?

        def initialize(
          @kind : Kind,
          @content : String,
          @tool_calls : Array(ToolCall) = [] of ToolCall,
          @prefix : Bool = false,
          @name : String? = nil,
          @tool_call_id : String? = nil,
        )
        end

        def self.user(content : String) : self
          new(Kind::User, content)
        end

        def self.assistant(content : String, tool_calls : Array(ToolCall) = [] of ToolCall, prefix : Bool = false) : self
          new(Kind::Assistant, content, tool_calls, prefix)
        end

        def self.system(content : String) : self
          new(Kind::System, content)
        end

        def self.tool(name : String, content : String, tool_call_id : String) : self
          new(Kind::Tool, content, name: name, tool_call_id: tool_call_id)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          role = hash["role"].as_s
          case role
          when "user"
            user(hash["content"].as_s)
          when "assistant"
            assistant(
              hash["content"]?.try(&.as_s?) || "",
              hash["tool_calls"]?.try(&.as_a.map { |entry| ToolCall.from_json_value(entry) }) || [] of ToolCall,
              hash["prefix"]?.try(&.as_bool?) || false,
            )
          when "system"
            system(hash["content"].as_s)
          when "tool"
            tool(hash["name"].as_s, hash["content"].as_s, hash["tool_call_id"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unknown Mistral message role: #{role}")
          end
        end

        def self.from_core_message(message : Crig::Completion::Message) : Array(self)
          return convert_user_message(message) if message.role.user?
          convert_assistant_message(message)
        end

        private def self.convert_user_message(message : Crig::Completion::Message) : Array(self)
          tool_result_messages = [] of self
          other_messages = [] of self

          message.content.each do |entry|
            content = entry.as(Crig::Completion::UserContent)
            if content.kind.tool_result?
              tool_result = content.tool_result || raise Crig::Completion::MessageError.new("Missing tool result content")
              call_id = tool_result.call_id || tool_result.id
              content_text = tool_result.content.to_a.find_value("") do |tool_result_content|
                tool_result_content.text.try(&.text)
              end
              tool_result_messages << tool(tool_result.id, content_text, call_id)
            elsif content.kind.text?
              text = content.text || raise Crig::Completion::MessageError.new("Missing user text content")
              other_messages << user(text.text)
            end
          end

          tool_result_messages.concat(other_messages)
          tool_result_messages
        end

        private def self.convert_assistant_message(message : Crig::Completion::Message) : Array(self)
          text_content = [] of Crig::Completion::Text
          tool_calls = [] of Crig::Completion::ToolCall

          message.content.each do |entry|
            content = entry.as(Crig::Completion::AssistantContent)
            case content.kind
            in .text?
              text = content.text || raise Crig::Completion::MessageError.new("Missing assistant text content")
              text_content << text
            in .tool_call?
              tool_call = content.tool_call || raise Crig::Completion::MessageError.new("Missing assistant tool-call content")
              tool_calls << tool_call
            in .reasoning?
            in .image?
              raise Crig::Completion::MessageError.new("Image content is not currently supported on Mistral via Crig")
            end
          end

          return [] of self if text_content.empty? && tool_calls.empty?

          [assistant(text_content.first?.try(&.text) || "", tool_calls.map { |tool_call| ToolCall.from_core(tool_call) }, false)]
        end

        def to_core_message : Crig::Completion::Message
          case @kind
          in .user?
            Crig::Completion::Message.user(@content)
          in .assistant?
            parts = [] of Crig::Completion::AssistantContent
            parts << Crig::Completion::AssistantContent.text(@content) unless @content.empty?
            @tool_calls.each do |call|
              parts << Crig::Completion::AssistantContent.tool_call(call.id, call.function.name, call.function.arguments)
            end
            Crig::Completion::Message.assistant(Crig::OneOrMany(Crig::Completion::AssistantContent).many(parts))
          in .tool?
            name = @name || raise Crig::Completion::CompletionError.new("Missing Mistral tool name")
            tool_call_id = @tool_call_id || raise Crig::Completion::CompletionError.new("Missing Mistral tool_call_id")
            Crig::Completion::Message.user(
              Crig::OneOrMany(Crig::Completion::UserContent).one(
                Crig::Completion::UserContent.tool_result(
                  name,
                  Crig::OneOrMany(Crig::Completion::ToolResultContent).one(Crig::Completion::ToolResultContent.text(@content)),
                  tool_call_id
                )
              )
            )
          in .system?
            Crig::Completion::Message.user(@content)
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .user?
              json.field "role", "user"
              json.field "content", @content
            in .assistant?
              json.field "role", "assistant"
              json.field "content", @content
              unless @tool_calls.empty?
                json.field "tool_calls" do
                  json.array do
                    @tool_calls.each do |tool_call|
                      json.object do
                        json.field "id", tool_call.id
                        json.field "type", tool_call.type.to_wire
                        json.field "function" { tool_call.function.to_json(json) }
                      end
                    end
                  end
                end
              end
              json.field "prefix", @prefix
            in .system?
              json.field "role", "system"
              json.field "content", @content
            in .tool?
              json.field "role", "tool"
              json.field "name", @name
              json.field "content", @content
              json.field "tool_call_id", @tool_call_id
            end
          end
        end
      end

      struct Choice
        getter index : Int32
        getter message : Message
        getter logprobs : JSON::Any?
        getter finish_reason : String

        def initialize(@index : Int32, @message : Message, @finish_reason : String, @logprobs : JSON::Any? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["index"].as_i,
            Message.from_json_value(hash["message"]),
            hash["finish_reason"].as_s,
            hash["logprobs"]?,
          )
        end
      end

      struct CompletionResponse
        getter id : String
        getter object : String
        getter created : Int64
        getter model : String
        getter system_fingerprint : String?
        getter choices : Array(Choice)
        getter usage : Usage?

        def initialize(
          @id : String,
          @object : String,
          @created : Int64,
          @model : String,
          @choices : Array(Choice),
          @usage : Usage? = nil,
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
            hash["choices"].as_a.map { |entry| Choice.from_json_value(entry) },
            hash["usage"]?.try { |entry| Usage.from_json(entry.to_json) },
            hash["system_fingerprint"]?.try(&.as_s?),
          )
        end

        def self.new(pull : JSON::PullParser)
          from_json_value(JSON.parse(pull.read_raw))
        end

        def token_usage : Crig::Completion::Usage?
          @usage.try(&.token_usage)
        end

        def to_completion_response : Crig::Completion::CompletionResponse(self)
          choice = @choices.first? || raise Crig::Completion::CompletionError.new("Response contained no choices")
          raise Crig::Completion::CompletionError.new("Response did not contain a valid message or tool call") unless choice.message.kind.assistant?

          content = [] of Crig::Completion::AssistantContent
          content << Crig::Completion::AssistantContent.text(choice.message.content) unless choice.message.content.empty?
          choice.message.tool_calls.each do |call|
            content << Crig::Completion::AssistantContent.tool_call(call.id, call.function.name, call.function.arguments)
          end
          raise Crig::Completion::CompletionError.new("Response contained no message or tool call (empty)") if content.empty?

          Crig::Completion::CompletionResponse(self).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).many(content),
            @usage.try(&.token_usage) || Crig::Completion::Usage.new,
            self,
          )
        end
      end

      def self.assistant_content_to_streaming_choice(content : Crig::Completion::AssistantContent) : Crig::RawStreamingChoice(CompletionResponse)?
        case content.kind
        in .text?
          text = content.text || raise Crig::Completion::CompletionError.new("Missing assistant text content")
          Crig::RawStreamingChoice(CompletionResponse).message(text.text)
        in .tool_call?
          tool_call = content.tool_call || raise Crig::Completion::CompletionError.new("Missing assistant tool-call content")
          Crig::RawStreamingChoice(CompletionResponse).tool_call(
            Crig::RawStreamingToolCall.new(tool_call.id, tool_call.function.name, tool_call.function.arguments)
          )
        in .reasoning?
          nil
        in .image?
          raise Crig::Completion::CompletionError.new("Image content is not supported on Mistral via Crig")
        end
      end

      struct MistralCompletionRequest
        getter model : String
        getter messages : Array(Message)
        getter temperature : Float64?
        getter tools : Array(ToolDefinition)
        getter tool_choice : Crig::Providers::OpenAI::Chat::ToolChoice?
        getter additional_params : JSON::Any?

        def initialize(
          @model : String,
          @messages : Array(Message),
          @temperature : Float64? = nil,
          @tools : Array(ToolDefinition) = [] of ToolDefinition,
          @tool_choice : Crig::Providers::OpenAI::Chat::ToolChoice? = nil,
          @additional_params : JSON::Any? = nil,
        )
        end

        def self.from_request(default_model : String, req : Crig::Completion::Request::CompletionRequest) : self
          model = req.model || default_model
          full_history = [] of Message
          if preamble = req.preamble
            full_history << Message.system(preamble)
          end
          if docs = req.normalized_documents
            Message.from_core_message(docs).each { |item| full_history << item }
          end
          req.chat_history.each do |message|
            Message.from_core_message(message).each { |item| full_history << item }
          end
          raise Crig::Completion::CompletionError.new("Mistral request has no provider-compatible messages after conversion") if full_history.empty?

          tool_choice = req.tool_choice.try do |choice|
            converted_tool_choice = ToolChoice.from_core(choice)
            if converted_tool_choice.auto?
              Crig::Providers::OpenAI::Chat::ToolChoice::Auto
            elsif converted_tool_choice.none?
              Crig::Providers::OpenAI::Chat::ToolChoice::None
            else
              Crig::Providers::OpenAI::Chat::ToolChoice::Required
            end
          end

          new(
            model,
            full_history,
            req.temperature,
            req.tools.map { |tool| ToolDefinition.from_core(tool) },
            tool_choice,
            req.additional_params,
          )
        end

        def to_json_value : JSON::Any
          payload = Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              json.field "model", @model
              json.field "messages" do
                json.array do
                  @messages.each(&.to_json(json))
                end
              end
              json.field "temperature", @temperature unless @temperature.nil?
              unless @tools.empty?
                json.field "tools" do
                  json.array do
                    @tools.each(&.to_json(json))
                  end
                end
              end
              if tool_choice = @tool_choice
                json.field "tool_choice", tool_choice.to_wire
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

        def self.with_model(client : Client, model : String) : self
          new(client, model)
        end

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          span = Crig::Span.chat_span("mistral", @model, request.preamble, nil)

          payload = MistralCompletionRequest.from_request(@model, request).to_json_value
          response = @client.post_json("/v1/chat/completions", payload.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          body = ApiResponse(CompletionResponse).from_json_value(parsed) { |value| CompletionResponse.from_json(value.to_json) }
          if error = body.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          response_body = body.ok || raise Crig::Completion::CompletionError.new("Mistral response did not include a success payload")
          result = response_body.to_completion_response
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          response = completion(request)
          raw_choices = [] of Crig::RawStreamingChoice(CompletionResponse)
          response.choice.each do |content|
            if choice = Crig::Providers::Mistral.assistant_content_to_streaming_choice(content)
              raw_choices << choice
            end
          end
          raw_choices << Crig::RawStreamingChoice(CompletionResponse).final_response(response.raw_response)
          Crig::StreamingCompletionResponse(CompletionResponse).stream_raw_choices(raw_choices)
        end
      end
    end
  end
end
