module Crig
  module Providers
    module DeepSeek
      DEEPSEEK_API_BASE_URL = "https://api.deepseek.com"
      DEEPSEEK_CHAT         = "deepseek-chat"
      DEEPSEEK_REASONER     = "deepseek-reasoner"

      struct DeepSeekExt
      end

      struct DeepSeekExtBuilder
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String

        def initialize(@api_key : String? = nil, @base_url : String = DEEPSEEK_API_BASE_URL)
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url)
        end

        def build : Client
          api_key = @api_key || raise "DEEPSEEK_API_KEY not set"
          Client.new(api_key, @base_url)
        end
      end

      struct ApiErrorResponse
        include JSON::Serializable

        getter message : String

        def initialize(@message : String)
        end
      end

      struct ApiResponse(T)
        getter ok : T?
        getter error : ApiErrorResponse?

        def initialize(@ok : T? = nil, @error : ApiErrorResponse? = nil)
        end

        def self.from_json_value(value : JSON::Any, & : JSON::Any -> T) : self
          if message = value["message"]?.try(&.as_s?)
            new(error: ApiErrorResponse.new(message))
          else
            new(ok: yield value)
          end
        end
      end

      struct Client
        getter api_key : String
        getter base_url : String

        def initialize(@api_key : String, @base_url : String = DEEPSEEK_API_BASE_URL)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["DEEPSEEK_API_KEY"]? || raise "DEEPSEEK_API_KEY not set"
          new(api_key)
        end

        def self.from_val(input : String) : self
          new(input)
        end

        def default_headers(accept : String = "application/json") : HTTP::Headers
          HTTP::Headers{
            "Authorization" => "Bearer #{@api_key}",
            "Content-Type"  => "application/json",
            "Accept"        => accept,
          }
        end

        def post_json(path : String, body : String, accept : String = "application/json") : HTTP::Client::Response
          HTTP::Client.exec("POST", build_uri(path), headers: default_headers(accept), body: body)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end
      end

      struct CompletionTokensDetails
        include JSON::Serializable

        @[JSON::Field(key: "reasoning_tokens")]
        getter reasoning_tokens : Int32?

        def initialize(@reasoning_tokens : Int32? = nil)
        end
      end

      struct PromptTokensDetails
        include JSON::Serializable

        @[JSON::Field(key: "cached_tokens")]
        getter cached_tokens : Int32?

        def initialize(@cached_tokens : Int32? = nil)
        end
      end

      struct Usage
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        @[JSON::Field(key: "completion_tokens")]
        getter completion_tokens : Int32 = 0
        @[JSON::Field(key: "prompt_tokens")]
        getter prompt_tokens : Int32 = 0
        @[JSON::Field(key: "prompt_cache_hit_tokens")]
        getter prompt_cache_hit_tokens : Int32 = 0
        @[JSON::Field(key: "prompt_cache_miss_tokens")]
        getter prompt_cache_miss_tokens : Int32 = 0
        @[JSON::Field(key: "total_tokens")]
        getter total_tokens : Int32 = 0
        @[JSON::Field(key: "completion_tokens_details")]
        getter completion_tokens_details : CompletionTokensDetails?
        @[JSON::Field(key: "prompt_tokens_details")]
        getter prompt_tokens_details : PromptTokensDetails?

        def initialize(
          @completion_tokens : Int32 = 0,
          @prompt_tokens : Int32 = 0,
          @prompt_cache_hit_tokens : Int32 = 0,
          @prompt_cache_miss_tokens : Int32 = 0,
          @total_tokens : Int32 = 0,
          @completion_tokens_details : CompletionTokensDetails? = nil,
          @prompt_tokens_details : PromptTokensDetails? = nil,
        )
        end

        def self.new_empty : self
          new
        end

        def token_usage : Crig::Completion::Usage?
          Crig::Completion::Usage.new(
            input_tokens: @prompt_tokens.to_i64,
            output_tokens: @completion_tokens.to_i64,
            total_tokens: @total_tokens.to_i64,
            cached_input_tokens: (@prompt_tokens_details.try(&.cached_tokens) || 0).to_i64,
          )
        end
      end

      struct Function
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

      enum ToolType
        Function

        def to_wire : String
          "function"
        end

        def self.from_wire(value : String?) : self
          case value
          when nil, "function" then Function
          else
            raise Crig::Completion::CompletionError.new("Unknown DeepSeek tool type: #{value}")
          end
        end
      end

      struct ToolCall
        getter id : String
        getter index : Int32
        getter type : ToolType
        getter function : Function

        def initialize(@id : String, @function : Function, @index : Int32 = 0, @type : ToolType = ToolType::Function)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["id"].as_s,
            Function.from_json_value(hash["function"]),
            hash["index"]?.try(&.as_i) || 0,
            ToolType.from_wire(hash["type"]?.try(&.as_s?)),
          )
        end

        def self.from_core(tool_call : Crig::Completion::ToolCall) : self
          new(tool_call.id, Function.new(tool_call.function.name, tool_call.function.arguments))
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "id", @id
            json.field "index", @index
            json.field "type", @type.to_wire
            json.field "function" { @function.to_json(json) }
          end
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

      struct Message
        enum Kind
          System
          User
          Assistant
          ToolResult
        end

        getter kind : Kind
        getter content : String
        getter name : String?
        getter tool_calls : Array(ToolCall)
        getter reasoning_content : String?
        getter tool_call_id : String?

        def initialize(
          @kind : Kind,
          @content : String,
          @name : String? = nil,
          @tool_calls : Array(ToolCall) = [] of ToolCall,
          @reasoning_content : String? = nil,
          @tool_call_id : String? = nil,
        )
        end

        def self.system(content : String) : self
          new(Kind::System, content)
        end

        def self.user(content : String, name : String? = nil) : self
          new(Kind::User, content, name)
        end

        def self.assistant(content : String, name : String? = nil, tool_calls : Array(ToolCall) = [] of ToolCall, reasoning_content : String? = nil) : self
          new(Kind::Assistant, content, name, tool_calls, reasoning_content)
        end

        def self.tool_result(tool_call_id : String, content : String) : self
          new(Kind::ToolResult, content, tool_call_id: tool_call_id)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          role = hash["role"].as_s
          case role
          when "system"
            system(hash["content"].as_s)
          when "user"
            user(hash["content"].as_s, hash["name"]?.try(&.as_s?))
          when "assistant"
            assistant(
              hash["content"]?.try(&.as_s?) || "",
              hash["name"]?.try(&.as_s?),
              hash["tool_calls"]?.try(&.as_a.map { |entry| ToolCall.from_json_value(entry) }) || [] of ToolCall,
              hash["reasoning_content"]?.try(&.as_s?),
            )
          when "tool"
            tool_result(hash["tool_call_id"].as_s, hash["content"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unknown DeepSeek message role")
          end
        end

        def self.from_core_messages(message : Crig::Completion::Message) : Array(self)
          case message.role
          in .user?
            convert_user_message(message)
          in .assistant?
            [convert_assistant_message(message)]
          end
        end

        private def self.convert_user_message(message : Crig::Completion::Message) : Array(self)
          tool_results = [] of Message
          text_parts = [] of String

          message.content.each do |entry|
            user_content = entry.as?(Crig::Completion::UserContent) || raise Crig::Completion::MessageError.new("Only user content is supported by DeepSeek")
            case user_content.kind
            in .tool_result?
              tool_result = user_content.tool_result || raise Crig::Completion::MessageError.new("Missing tool result content")
              content = case tool_result.content.first.kind
                        in .text?
                          tool_result.content.first.text.try(&.text) || ""
                        in .image?
                          "[Image]"
                        end
              tool_results << Message.tool_result(tool_result.id, content)
            in .text?
              text = user_content.text.try(&.text) || ""
              text_parts << text
            in .document?
              document = user_content.document || raise Crig::Completion::MessageError.new("Missing document content")
              case document.data.kind
              in .base64?, .string?
                if content = document.data.try_into_inner
                  text_parts << content
                end
              in .url?, .raw?, .unknown?
              end
            in .image?, .audio?, .video?
            end
          end

          messages = tool_results
          merged = text_parts.join('\n')
          messages << Message.user(merged) unless merged.empty?
          messages
        end

        private def self.convert_assistant_message(message : Crig::Completion::Message) : self
          text_content = String.build do |io|
            message.content.each do |entry|
              assistant_content = entry.as?(Crig::Completion::AssistantContent)
              next unless assistant_content && assistant_content.kind.text?
              io << (assistant_content.text.try(&.text) || "")
            end
          end

          reasoning_content = String.build do |io|
            message.content.each do |entry|
              assistant_content = entry.as?(Crig::Completion::AssistantContent)
              next unless assistant_content && assistant_content.kind.reasoning?
              io << (assistant_content.reasoning.try(&.display_text) || "")
            end
          end

          tool_calls = message.content.compact_map do |entry|
            assistant_content = entry.as?(Crig::Completion::AssistantContent)
            next unless assistant_content && assistant_content.kind.tool_call?
            tool_call = assistant_content.tool_call || raise Crig::Completion::MessageError.new("Missing assistant tool call")
            ToolCall.from_core(tool_call)
          end

          assistant(
            text_content,
            nil,
            tool_calls,
            reasoning_content.empty? ? nil : reasoning_content,
          )
        end

        def to_core_message : Crig::Completion::Message
          case @kind
          in .system?
            Crig::Completion::Message.user(@content)
          in .user?
            Crig::Completion::Message.user(@content)
          in .assistant?
            content = [] of Crig::Completion::AssistantContent
            content << Crig::Completion::AssistantContent.text(@content) unless @content.empty?
            @tool_calls.each do |tool_call|
              content << Crig::Completion::AssistantContent.tool_call(tool_call.id, tool_call.function.name, tool_call.function.arguments)
            end
            if reasoning = @reasoning_content
              content << Crig::Completion::AssistantContent.reasoning(reasoning)
            end
            choice = Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
              content.map(&.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent))
            ) || raise Crig::Completion::CompletionError.new("Response did not contain a valid message or tool call")
            Crig::Completion::Message.new(Crig::Completion::Message::Role::Assistant, choice)
          in .tool_result?
            Crig::Completion::Message.tool_result(@tool_call_id || "", @content)
          end
        end

        def to_json_value : JSON::Any
          Crig::Providers::OpenAI.build_json_any do |json|
            json.object do
              case @kind
              in .system?
                json.field "role", "system"
                json.field "content", @content
                json.field "name", @name unless @name.nil?
              in .user?
                json.field "role", "user"
                json.field "content", @content
                json.field "name", @name unless @name.nil?
              in .assistant?
                json.field "role", "assistant"
                json.field "content", @content
                json.field "name", @name unless @name.nil?
                unless @tool_calls.empty?
                  json.field "tool_calls" { json.array { @tool_calls.each(&.to_json(json)) } }
                end
                json.field "reasoning_content", @reasoning_content unless @reasoning_content.nil?
              in .tool_result?
                json.field "role", "tool"
                json.field "tool_call_id", @tool_call_id
                json.field "content", @content
              end
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
        getter choices : Array(Choice)
        getter usage : Usage

        def initialize(@choices : Array(Choice), @usage : Usage)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["choices"].as_a.map { |entry| Choice.from_json_value(entry) },
            Usage.from_json(hash["usage"].to_json),
          )
        end

        def to_crig_response : Crig::Completion::CompletionResponse(self)
          choice = @choices.first? || raise Crig::Completion::CompletionError.new("Response contained no choices")
          unless choice.message.kind.assistant?
            raise Crig::Completion::CompletionError.new("Response did not contain a valid message or tool call")
          end

          content = [] of Crig::Completion::AssistantContent
          content << Crig::Completion::AssistantContent.text(choice.message.content) unless choice.message.content.strip.empty?
          choice.message.tool_calls.each do |call|
            content << Crig::Completion::AssistantContent.tool_call(call.id, call.function.name, call.function.arguments)
          end
          if reasoning = choice.message.reasoning_content
            content << Crig::Completion::AssistantContent.reasoning(reasoning)
          end
          choice_value = Crig::OneOrMany(Crig::Completion::AssistantContent).many(content) || raise Crig::Completion::CompletionError.new("Response contained no message or tool call (empty)")

          Crig::Completion::CompletionResponse(self).new(
            choice_value,
            @usage.token_usage || Crig::Completion::Usage.new,
            self,
          )
        end
      end

      struct DeepseekCompletionRequest
        getter model : String
        getter messages : Array(Message)
        getter temperature : Float64?
        getter tools : Array(ToolDefinition)
        getter tool_choice : Crig::Providers::OpenRouter::ToolChoice?
        getter additional_params : JSON::Any?

        def initialize(
          @model : String,
          @messages : Array(Message),
          @temperature : Float64? = nil,
          @tools : Array(ToolDefinition) = [] of ToolDefinition,
          @tool_choice : Crig::Providers::OpenRouter::ToolChoice? = nil,
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
            full_history.concat(Message.from_core_messages(docs))
          end
          req.chat_history.each do |message|
            full_history.concat(Message.from_core_messages(message))
          end
          tool_choice = req.tool_choice.try { |choice| Crig::Providers::OpenRouter::ToolChoice.from_core(choice) }
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
                json.array { @messages.each(&.to_json_value.to_json(json)) }
              end
              json.field "temperature", @temperature unless @temperature.nil?
              unless @tools.empty?
                json.field "tools" { json.array { @tools.each(&.to_json(json)) } }
              end
              if tool_choice = @tool_choice
                json.field "tool_choice" { tool_choice.to_json_value.to_json(json) }
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

      struct StreamingDelta
        getter content : String?
        getter tool_calls : Array(StreamingToolCall)
        getter reasoning_content : String?

        def initialize(@content : String? = nil, @tool_calls : Array(StreamingToolCall) = [] of StreamingToolCall, @reasoning_content : String? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["content"]?.try(&.as_s?),
            hash["tool_calls"]?.try(&.as_a.map { |entry| StreamingToolCall.from_json_value(entry) }) || [] of StreamingToolCall,
            hash["reasoning_content"]?.try(&.as_s?),
          )
        end
      end

      struct StreamingChoice
        getter delta : StreamingDelta

        def initialize(@delta : StreamingDelta)
        end

        def self.from_json_value(value : JSON::Any) : self
          new(StreamingDelta.from_json_value(value["delta"]))
        end
      end

      struct StreamingCompletionChunk
        getter choices : Array(StreamingChoice)
        getter usage : Usage?

        def initialize(@choices : Array(StreamingChoice), @usage : Usage? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["choices"]?.try(&.as_a.map { |entry| StreamingChoice.from_json_value(entry) }) || [] of StreamingChoice,
            hash["usage"]?.try { |entry| Usage.from_json(entry.to_json) },
          )
        end
      end

      struct StreamingCompletionResponse
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter usage : Usage

        def initialize(@usage : Usage)
        end

        def token_usage : Crig::Completion::Usage?
          @usage.token_usage
        end
      end

      struct StreamingToolFunction
        getter name : String?
        getter arguments : String?

        def initialize(@name : String? = nil, @arguments : String? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(hash["name"]?.try(&.as_s?), hash["arguments"]?.try(&.as_s?))
        end
      end

      struct StreamingToolCall
        getter id : String?
        getter index : Int32
        getter function : StreamingToolFunction

        def initialize(@index : Int32, @function : StreamingToolFunction, @id : String? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["index"]?.try(&.as_i) || 0,
            StreamingToolFunction.from_json_value(hash["function"]),
            hash["id"]?.try(&.as_s?),
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

        def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
          Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt).model(@model)
        end

        def completion(request : Crig::Completion::Request::CompletionRequest)
          payload = DeepseekCompletionRequest.from_request(@model, request).to_json_value
          response = @client.post_json("/chat/completions", payload.to_json)
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400

          parsed = JSON.parse(text)
          body = ApiResponse(CompletionResponse).from_json_value(parsed) { |value| CompletionResponse.from_json_value(value) }
          if error = body.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          response_body = body.ok || raise Crig::Completion::CompletionError.new("DeepSeek response did not include a success payload")
          response_body.to_crig_response
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = DeepseekCompletionRequest.from_request(@model, request)
          stream_params = if additional_params = payload.additional_params
                            Crig::Providers::OpenAI.merge_json_values(additional_params, JSON.parse(%({"stream":true,"stream_options":{"include_usage":true}})))
                          else
                            JSON.parse(%({"stream":true,"stream_options":{"include_usage":true}}))
                          end
          request_payload = DeepseekCompletionRequest.new(payload.model, payload.messages, payload.temperature, payload.tools, payload.tool_choice, stream_params)
          response = @client.post_json("/chat/completions", request_payload.to_json_value.to_json, "text/event-stream")
          text = response.body
          raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400
          Crig::StreamingCompletionResponse(StreamingCompletionResponse).from_raw_choices(parse_streaming_choices(text))
        end

        private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(StreamingCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(StreamingCompletionResponse)
          final_usage = Usage.new_empty
          calls = {} of Int32 => {String, String, String}

          text.each_line do |line|
            chunk = parse_stream_chunk(line)
            next unless chunk

            if choice = chunk.choices.first?
              append_tool_call_choices(raw_choices, calls, choice.delta)
              append_reasoning_choice(raw_choices, choice.delta)
              append_text_choice(raw_choices, choice.delta)
            end

            if usage = chunk.usage
              final_usage = usage
            end
          end

          flush_deferred_tool_calls(raw_choices, calls)

          raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).final_response(
            StreamingCompletionResponse.new(final_usage)
          )
          raw_choices
        end

        private def parse_stream_chunk(line : String) : StreamingCompletionChunk?
          return unless line.starts_with?("data:")
          data_str = line[5..].to_s.strip
          return if data_str.empty? || data_str == "[DONE]"
          StreamingCompletionChunk.from_json_value(JSON.parse(data_str))
        end

        private def append_tool_call_choices(
          raw_choices : Array(Crig::RawStreamingChoice(StreamingCompletionResponse)),
          calls : Hash(Int32, {String, String, String}),
          delta : StreamingDelta,
        ) : Nil
          return if delta.tool_calls.empty?

          delta.tool_calls.each do |tool_call|
            if start_of_tool_call?(tool_call)
              calls[tool_call.index] = {tool_call.id || "", tool_call.function.name || "", ""}
            elsif continuation_of_tool_call?(tool_call)
              append_tool_call_arguments(calls, tool_call)
            else
              append_complete_tool_call(raw_choices, tool_call)
            end
          end
        end

        private def start_of_tool_call?(tool_call : StreamingToolCall) : Bool
          function = tool_call.function
          function.name.try(&.empty?) == false && (function.arguments.nil? || function.arguments == "")
        end

        private def continuation_of_tool_call?(tool_call : StreamingToolCall) : Bool
          function = tool_call.function
          function.name.to_s.empty? && function.arguments.to_s != ""
        end

        private def append_tool_call_arguments(calls : Hash(Int32, {String, String, String}), tool_call : StreamingToolCall) : Nil
          current = calls[tool_call.index]?
          return unless current
          calls[tool_call.index] = {current[0], current[1], "#{current[2]}#{tool_call.function.arguments}"}
        end

        private def append_complete_tool_call(
          raw_choices : Array(Crig::RawStreamingChoice(StreamingCompletionResponse)),
          tool_call : StreamingToolCall,
        ) : Nil
          id = tool_call.id || ""
          name = tool_call.function.name || ""
          arguments_str = tool_call.function.arguments || ""
          arguments_json = parse_tool_arguments(arguments_str)
          return unless arguments_json

          raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
            Crig::RawStreamingToolCall.new(id, name, arguments_json)
          )
        end

        private def append_reasoning_choice(
          raw_choices : Array(Crig::RawStreamingChoice(StreamingCompletionResponse)),
          delta : StreamingDelta,
        ) : Nil
          if reasoning = delta.reasoning_content
            raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).reasoning_delta(nil, reasoning)
          end
        end

        private def append_text_choice(
          raw_choices : Array(Crig::RawStreamingChoice(StreamingCompletionResponse)),
          delta : StreamingDelta,
        ) : Nil
          if content = delta.content
            raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).message(content)
          end
        end

        private def flush_deferred_tool_calls(
          raw_choices : Array(Crig::RawStreamingChoice(StreamingCompletionResponse)),
          calls : Hash(Int32, {String, String, String}),
        ) : Nil
          indexes = calls.keys
          indexes.sort!
          indexes.each do |index|
            id, name, arguments = calls[index]
            arguments_json = parse_tool_arguments(arguments)
            next unless arguments_json

            raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
              Crig::RawStreamingToolCall.new(id, name, arguments_json)
            )
          end
        end

        private def parse_tool_arguments(arguments : String) : JSON::Any?
          JSON.parse(arguments)
        rescue
          nil
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::DeepSeek::CompletionModel)
      end
    end
  end
end
