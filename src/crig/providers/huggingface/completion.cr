module Crig
  module Providers
    module HuggingFace
      GEMMA_2              = "google/gemma-2-2b-it"
      META_LLAMA_3_1       = "meta-llama/Meta-Llama-3.1-8B-Instruct"
      SMALLTHINKER_PREVIEW = "PowerInfer/SmallThinker-3B-Preview"
      QWEN2_5              = "Qwen/Qwen2.5-7B-Instruct"
      QWEN2_5_CODER        = "Qwen/Qwen2.5-Coder-32B-Instruct"
      QWEN2_VL             = "Qwen/Qwen2-VL-7B-Instruct"
      QWEN_QVQ_PREVIEW     = "Qwen/QVQ-72B-Preview"

      struct ApiResponse(T)
        getter ok : T?
        getter error : JSON::Any?

        def initialize(@ok : T? = nil, @error : JSON::Any? = nil)
        end

        def self.from_json_value(value : JSON::Any, & : JSON::Any -> T) : self
          if value.raw.is_a?(Hash) && !value.as_h["choices"]?
            new(error: value)
          else
            new(ok: yield value)
          end
        end
      end

      struct Function
        getter name : String
        getter arguments : JSON::Any

        def initialize(@name : String, @arguments : JSON::Any)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          arguments_value = hash["arguments"]
          arguments = arguments_value.as_s?.try { |text| JSON.parse(text) } || arguments_value
          new(hash["name"].as_s, arguments)
        end
      end

      enum ToolType
        Function

        def to_json(json : JSON::Builder) : Nil
          json.string("function")
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

      struct ToolCall
        getter id : String
        getter type : ToolType
        getter function : Function

        def initialize(@id : String, @function : Function, @type : ToolType = ToolType::Function)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["id"].as_s,
            Function.from_json_value(hash["function"]),
            ToolType::Function,
          )
        end

        def self.from_core(tool_call : Crig::Completion::ToolCall) : self
          new(tool_call.id, Function.new(tool_call.function.name, tool_call.function.arguments))
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
            image_url(hash["image_url"]["url"].as_s)
          else
            raise Crig::Completion::CompletionError.new("Unsupported HuggingFace user content type: #{hash["type"].as_s}")
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
              image_url = @image_url || raise Crig::Completion::CompletionError.new("Missing HuggingFace image_url content")
              json.field "image_url" { image_url.to_json(json) }
            end
          end
        end
      end

      struct AssistantContent
        getter text : String

        def initialize(@text : String)
        end

        def self.text(text : String) : self
          new(text)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(hash["text"].as_s)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "type", "text"
            json.field "text", @text
          end
        end
      end

      struct SystemContent
        getter text : String

        def initialize(@text : String)
        end

        def self.text(text : String) : self
          new(text)
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "type", "text"
            json.field "text", @text
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
        getter system_content : Crig::OneOrMany(SystemContent)?
        getter user_content : Crig::OneOrMany(UserContent)?
        getter assistant_content : Array(AssistantContent)
        getter tool_calls : Array(ToolCall)
        getter tool_result_name : String?
        getter arguments : JSON::Any?
        getter tool_result_content : Crig::OneOrMany(String)?

        def initialize(
          @kind : Kind,
          @system_content : Crig::OneOrMany(SystemContent)? = nil,
          @user_content : Crig::OneOrMany(UserContent)? = nil,
          @assistant_content : Array(AssistantContent) = [] of AssistantContent,
          @tool_calls : Array(ToolCall) = [] of ToolCall,
          @tool_result_name : String? = nil,
          @arguments : JSON::Any? = nil,
          @tool_result_content : Crig::OneOrMany(String)? = nil,
        )
        end

        def self.system(content : String) : self
          new(Kind::System, system_content: Crig::OneOrMany(SystemContent).one(SystemContent.text(content)))
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["role"].as_s
          when "system"
            content = parse_string_or_one_or_many(hash["content"]) { |entry| SystemContent.text(entry.as_s? || entry["text"].as_s) }
            new(Kind::System, system_content: content)
          when "user"
            content = parse_string_or_one_or_many(hash["content"]) do |entry|
              if text = entry.as_s?
                UserContent.text(text)
              else
                UserContent.from_json_value(entry)
              end
            end
            new(Kind::User, user_content: content)
          when "assistant"
            new(
              Kind::Assistant,
              assistant_content: parse_assistant_content(hash["content"]?),
              tool_calls: hash["tool_calls"]?.try(&.as_a?.try(&.map { |entry| ToolCall.from_json_value(entry) })) || [] of ToolCall,
            )
          when "tool", "Tool"
            content = parse_string_or_one_or_many(hash["content"]) { |entry| entry.as_s }
            new(
              Kind::ToolResult,
              tool_result_name: hash["name"].as_s,
              arguments: hash["arguments"]?,
              tool_result_content: content,
            )
          else
            raise Crig::Completion::CompletionError.new("Unsupported HuggingFace role: #{hash["role"].as_s}")
          end
        end

        def self.from_core_message(message : Crig::Completion::Message) : Array(self)
          if message.role.user?
            tool_results = [] of self
            other_content = [] of UserContent
            message.content.each do |item|
              content = item.as(Crig::Completion::UserContent)
              if content.kind.tool_result?
                tool_result = content.tool_result || raise Crig::Completion::MessageError.new("Missing tool result content")
                parts = tool_result.content.to_a.map do |tool_result_content|
                  text = tool_result_content.text || raise Crig::Completion::MessageError.new("Tool result content does not support non-text")
                  text.text
                end
                tool_results << Message.new(
                  Kind::ToolResult,
                  tool_result_name: tool_result.id,
                  tool_result_content: Crig::OneOrMany(String).many(parts),
                )
              else
                other_content << convert_user_content(content)
              end
            end
            return tool_results unless tool_results.empty?
            return [Message.new(Kind::User, user_content: Crig::OneOrMany(UserContent).many(other_content))] unless other_content.empty?
            return [] of self
          end

          text_content = [] of AssistantContent
          tool_calls = [] of ToolCall
          message.content.each do |item|
            content = item.as(Crig::Completion::AssistantContent)
            case content.kind
            in .text?
              text = content.text || raise Crig::Completion::MessageError.new("Missing assistant text content")
              text_content << AssistantContent.text(text.text)
            in .tool_call?
              tool_call = content.tool_call || raise Crig::Completion::MessageError.new("Missing assistant tool-call content")
              tool_calls << ToolCall.from_core(tool_call)
            in .reasoning?
            in .image?
              raise Crig::Completion::MessageError.new("Image content is not supported on HuggingFace via Crig")
            end
          end
          return [] of self if text_content.empty? && tool_calls.empty?
          [Message.new(Kind::Assistant, assistant_content: text_content, tool_calls: tool_calls)]
        end

        def to_core_message : Crig::Completion::Message
          case @kind
          in .user?
            user_content = @user_content || raise Crig::Completion::CompletionError.new("Missing HuggingFace user content")
            Crig::Completion::Message.new(
              Crig::Completion::Message::Role::User,
              Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
                user_content.map { |entry| self.class.convert_user_content_to_core(entry).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent) }
              )
            )
          in .assistant?
            content = @assistant_content.map { |entry| Crig::Completion::AssistantContent.text(entry.text) }
            content.concat(@tool_calls.map { |tool_call| Crig::Completion::AssistantContent.tool_call(tool_call.id, tool_call.function.name, tool_call.function.arguments) })
            Crig::Completion::Message.new(
              Crig::Completion::Message::Role::Assistant,
              Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
                content.map(&.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent))
              ),
            )
          in .tool_result?
            tool_result_name = @tool_result_name || raise Crig::Completion::CompletionError.new("Missing HuggingFace tool result name")
            tool_result_content = @tool_result_content || raise Crig::Completion::CompletionError.new("Missing HuggingFace tool result content")
            Crig::Completion::Message.new(
              Crig::Completion::Message::Role::User,
              Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
                Crig::Completion::UserContent.tool_result(
                  tool_result_name,
                  Crig::OneOrMany(Crig::Completion::ToolResultContent).many(
                    tool_result_content.map { |text| Crig::Completion::ToolResultContent.text(text) }
                  )
                ).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
              ),
            )
          in .system?
            system_content = @system_content || raise Crig::Completion::CompletionError.new("Missing HuggingFace system content")
            Crig::Completion::Message.new(
              Crig::Completion::Message::Role::User,
              Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
                system_content.map { |entry| Crig::Completion::UserContent.text(entry.text).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent) }
              )
            )
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            case @kind
            in .system?
              system_content = @system_content || raise Crig::Completion::CompletionError.new("Missing HuggingFace system content")
              json.field "role", "system"
              json.field "content" do
                serialize_string_or_many(json, system_content) { |entry| entry.to_json(json) }
              end
            in .user?
              user_content = @user_content || raise Crig::Completion::CompletionError.new("Missing HuggingFace user content")
              json.field "role", "user"
              json.field "content" do
                serialize_string_or_many(json, user_content) do |entry|
                  if entry.kind.text?
                    text = entry.text || raise Crig::Completion::CompletionError.new("Missing HuggingFace user text content")
                    json.string(text)
                  else
                    entry.to_json(json)
                  end
                end
              end
            in .assistant?
              json.field "role", "assistant"
              if @assistant_content.empty?
                json.field "content", nil
              else
                json.field "content" do
                  if @assistant_content.size == 1
                    @assistant_content.first.to_json(json)
                  else
                    json.array do
                      @assistant_content.each(&.to_json(json))
                    end
                  end
                end
              end
              json.field "tool_calls" do
                json.array do
                  @tool_calls.each do |tool_call|
                    json.object do
                      json.field "id", tool_call.id
                      json.field "type", "function"
                      json.field "function" do
                        json.object do
                          json.field "name", tool_call.function.name
                          json.field "arguments", tool_call.function.arguments
                        end
                      end
                    end
                  end
                end
              end unless @tool_calls.empty?
            in .tool_result?
              tool_result_content = @tool_result_content || raise Crig::Completion::CompletionError.new("Missing HuggingFace tool result content")
              json.field "role", "tool"
              json.field "name", @tool_result_name
              json.field "arguments", @arguments unless @arguments.nil?
              json.field "content", tool_result_content.to_a.join('\n')
            end
          end
        end

        private def self.parse_assistant_content(value : JSON::Any?) : Array(AssistantContent)
          return [] of AssistantContent unless value
          return [] of AssistantContent if value.raw.nil?
          if string = value.as_s?
            [AssistantContent.text(string)]
          else
            value.as_a.map { |entry| AssistantContent.from_json_value(entry) }
          end
        end

        private def self.parse_string_or_one_or_many(value : JSON::Any, & : JSON::Any -> T) : Crig::OneOrMany(T) forall T
          if string = value.as_s?
            Crig::OneOrMany(T).one(yield JSON::Any.new(string))
          else
            Crig::OneOrMany(T).many(value.as_a.map { |entry| yield entry })
          end
        end

        def self.convert_user_content(content : Crig::Completion::UserContent) : UserContent
          case content.kind
          in .text?
            text = content.text || raise Crig::Completion::MessageError.new("Missing user text content")
            UserContent.text(text.text)
          in .document?
            document = content.document || raise Crig::Completion::MessageError.new("Missing user document content")
            case document.data.kind
            in .raw?
              bytes = document.data.bytes_value || raise Crig::Completion::MessageError.new("Missing raw document bytes")
              UserContent.text(String.new(bytes))
            in .base64?, .string?
              string_value = document.data.string_value || raise Crig::Completion::MessageError.new("Missing string document content")
              UserContent.text(string_value)
            in .url?, .file_id?, .unknown?
              raise Crig::Completion::MessageError.new("HuggingFace only supports text and images")
            end
          in .image?
            image = content.image || raise Crig::Completion::MessageError.new("Missing user image content")
            UserContent.image_url(image.try_into_url)
          in .audio?, .video?, .tool_result?
            raise Crig::Completion::MessageError.new("HuggingFace only supports text and images")
          end
        end

        def self.convert_user_content_to_core(content : UserContent) : Crig::Completion::UserContent
          case content.kind
          in .text?
            text = content.text || raise Crig::Completion::CompletionError.new("Missing HuggingFace user text content")
            Crig::Completion::UserContent.text(text)
          in .image_url?
            image_url = content.image_url || raise Crig::Completion::CompletionError.new("Missing HuggingFace image_url content")
            Crig::Completion::UserContent.image_url(image_url.url)
          end
        end

        private def serialize_string_or_many(json : JSON::Builder, values : Crig::OneOrMany(T), & : T -> Nil) forall T
          if values.len == 1 && values.first.is_a?(UserContent) && values.first.as(UserContent).kind.text?
            text = values.first.as(UserContent).text || raise Crig::Completion::CompletionError.new("Missing HuggingFace user text content")
            json.string(text)
          elsif values.len == 1 && values.first.is_a?(SystemContent)
            yield values.first
          else
            json.array do
              values.each { |value| yield value }
            end
          end
        end
      end

      struct Choice
        include JSON::Serializable

        getter finish_reason : String
        getter index : Int32
        getter logprobs : JSON::Any
        getter message : Message

        def initialize(@finish_reason : String, @index : Int32, @message : Message, @logprobs : JSON::Any = JSON.parse("null"))
        end

        def self.new(pull : JSON::PullParser)
          from_json_value(JSON.parse(pull.read_raw))
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["finish_reason"].as_s,
            hash["index"].as_i,
            Message.from_json_value(hash["message"]),
            hash["logprobs"]? || JSON.parse("null"),
          )
        end
      end

      struct Usage
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter completion_tokens : Int32
        getter prompt_tokens : Int32
        getter total_tokens : Int32

        def initialize(@completion_tokens : Int32, @prompt_tokens : Int32, @total_tokens : Int32)
        end

        def token_usage : Crig::Completion::Usage?
          Crig::Completion::Usage.new(
            input_tokens: @prompt_tokens.to_i64,
            output_tokens: @completion_tokens.to_i64,
            total_tokens: @total_tokens.to_i64,
            cached_input_tokens: 0_i64,
          )
        end
      end

      struct CompletionResponse
        include JSON::Serializable

        getter created : Int32
        getter id : String
        getter model : String
        getter choices : Array(Choice)
        getter system_fingerprint : String
        getter usage : Usage

        def initialize(
          @created : Int32,
          @id : String,
          @model : String,
          @choices : Array(Choice),
          @usage : Usage,
          @system_fingerprint : String = "",
        )
        end

        def self.new(pull : JSON::PullParser)
          from_json_value(JSON.parse(pull.read_raw))
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["created"].as_i,
            hash["id"].as_s,
            hash["model"].as_s,
            hash["choices"].as_a.map { |entry| Choice.from_json_value(entry) },
            Usage.from_json(hash["usage"].to_json),
            hash["system_fingerprint"]?.try(&.as_s?) || "",
          )
        end

        def to_completion_response : Crig::Completion::CompletionResponse(self)
          choice = @choices.first? || raise Crig::Completion::CompletionError.new("Response contained no choices")
          raise Crig::Completion::CompletionError.new("Response did not contain a valid message or tool call") unless choice.message.kind.assistant?
          content = [] of Crig::Completion::AssistantContent
          choice.message.assistant_content.each do |entry|
            content << Crig::Completion::AssistantContent.text(entry.text)
          end
          choice.message.tool_calls.each do |call|
            content << Crig::Completion::AssistantContent.tool_call(call.id, call.function.name, call.function.arguments)
          end
          raise Crig::Completion::CompletionError.new("Response contained no message or tool call (empty)") if content.empty?

          Crig::Completion::CompletionResponse(self).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).many(content),
            Crig::Completion::Usage.new(
              input_tokens: @usage.prompt_tokens.to_i64,
              output_tokens: @usage.completion_tokens.to_i64,
              total_tokens: @usage.total_tokens.to_i64,
              cached_input_tokens: 0_i64,
            ),
            self,
          )
        end
      end

      struct HuggingfaceCompletionRequest
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
          raise Crig::Completion::CompletionError.new("HuggingFace request has no provider-compatible messages after conversion") if full_history.empty?

          tool_choice = req.tool_choice.try do |choice|
            case choice.kind
            in .auto?     then Crig::Providers::OpenAI::Chat::ToolChoice::Auto
            in .none?     then Crig::Providers::OpenAI::Chat::ToolChoice::None
            in .required? then Crig::Providers::OpenAI::Chat::ToolChoice::Required
            in .specific?
              raise Crig::Completion::CompletionError.new("HuggingFace does not support specific function tool choice")
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

        def to_json(json : JSON::Builder) : Nil
          payload = Crig::Providers::OpenAI.build_json_any do |builder|
            builder.object do
              builder.field "model", @model
              builder.field "messages" do
                builder.array do
                  @messages.each(&.to_json(builder))
                end
              end
              builder.field "temperature", @temperature unless @temperature.nil?
              unless @tools.empty?
                builder.field "tools" do
                  builder.array do
                    @tools.each(&.to_json(builder))
                  end
                end
              end
              builder.field "tool_choice", @tool_choice.try(&.to_wire) unless @tool_choice.nil?
            end
          end
          merged = if params = @additional_params
                     JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(payload.as_h, params.as_h).to_json)
                   else
                     payload
                   end
          merged.to_json(json)
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
          span = Crig::Span.chat_span("huggingface", @model, request.preamble, nil)

          request_model = request.model || @model
          model_identifier = @client.subprovider.model_identifier(request_model)
          payload = HuggingfaceCompletionRequest.from_request(model_identifier, request)
          path = @client.subprovider.completion_endpoint(request_model)
          response = @client.post_json(path, payload.to_json)
          body = response.body
          raise Crig::Completion::CompletionError.new("#{response.status_code}: #{body}") if response.status_code >= 400

          parsed = JSON.parse(body)
          envelope = ApiResponse(CompletionResponse).from_json_value(parsed) { |value| CompletionResponse.from_json(value.to_json) }
          if error = envelope.error
            raise Crig::Completion::CompletionError.new(error.to_json)
          end
          completion_response = envelope.ok || raise Crig::Completion::CompletionError.new("HuggingFace response did not include a success payload")
          result = completion_response.to_completion_response
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          request_model = request.model || @model
          model_identifier = @client.subprovider.model_identifier(request_model)
          payload = HuggingfaceCompletionRequest.from_request(model_identifier, request)
          merged = if params = payload.additional_params
                     JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(params.as_h, JSON.parse(%({"stream":true,"stream_options":{"include_usage":true}})).as_h).to_json)
                   else
                     JSON.parse(%({"stream":true,"stream_options":{"include_usage":true}}))
                   end
          request_payload = HuggingfaceCompletionRequest.new(
            payload.model,
            payload.messages,
            payload.temperature,
            payload.tools,
            payload.tool_choice,
            merged,
          )
          path = @client.subprovider.completion_endpoint(request_model)
          response = @client.post_json(path, request_payload.to_json, "text/event-stream")
          body = response.body
          raise Crig::Completion::CompletionError.new("#{response.status_code}: #{body}") if response.status_code >= 400

          profile = StreamingProfile.new
          items, final_usage = Crig::Providers::Internal::OpenAICompatible.process_compatible_sse_stream(
            body, profile
          )
          raw_choices = items.map { |item| Crig::Providers::Internal::OpenAICompatible.convert_to_raw_choice(item, Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse) }
          raw_choices << Crig::RawStreamingChoice(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse).final_response(
            profile.build_final_response(final_usage)
          )
          Crig::StreamingCompletionResponse(Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse).stream_raw_choices(raw_choices)
        end

        private struct StreamingProfile
          def normalize_chunk(data : String) : Crig::Providers::Internal::OpenAICompatible::CompatibleChunk(Crig::Providers::OpenAI::OpenAIUsage)?
            json = JSON.parse(data)
            chunk = Crig::Providers::OpenAI::Chat::Streaming::CompletionChunk.from_json_value(json)

            choice = chunk.choices.first?
            tool_call_chunks = choice.try(&.delta.tool_calls).try(&.map { |tc|
              Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk.new(
                tc.index, tc.id, tc.function.name, tc.function.arguments,
              )
            }) || [] of Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk

            finish_reason = Crig::Providers::Internal::OpenAICompatible::CompatibleFinishReason::Other

            compat_choice = Crig::Providers::Internal::OpenAICompatible::CompatibleChoice.new(
              finish_reason: finish_reason,
              text: choice.try(&.delta.content),
              tool_calls: tool_call_chunks,
            )

            Crig::Providers::Internal::OpenAICompatible::CompatibleChunk(Crig::Providers::OpenAI::OpenAIUsage).new(
              choice: compat_choice,
              usage: chunk.usage,
            )
          end

          def build_final_response(usage : Crig::Providers::OpenAI::OpenAIUsage?) : Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse
            Crig::Providers::OpenAI::Chat::Streaming::CompletionResponse.new(usage)
          end

          def should_evict(
            existing : Crig::RawStreamingToolCall,
            incoming : Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk,
          ) : Bool
            false
          end

          def should_emit_completed_tool_call_immediately(
            tool_call : Crig::RawStreamingToolCall,
            incoming : Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk,
          ) : Bool
            false
          end
        end
      end
    end
  end
end
