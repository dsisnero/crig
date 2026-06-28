require "http/client"

module Crig
  module Providers
    module Galadriel
      GALADRIEL_API_BASE_URL = "https://api.galadriel.com/v1/verified"

      O1_PREVIEW                = "o1-preview"
      O1_PREVIEW_2024_09_12     = "o1-preview-2024-09-12"
      O1_MINI                   = "o1-mini"
      O1_MINI_2024_09_12        = "o1-mini-2024-09-12"
      GPT_4O                    = "gpt-4o"
      GPT_4O_2024_05_13         = "gpt-4o-2024-05-13"
      GPT_4_TURBO               = "gpt-4-turbo"
      GPT_4_TURBO_2024_04_09    = "gpt-4-turbo-2024-04-09"
      GPT_4_TURBO_PREVIEW       = "gpt-4-turbo-preview"
      GPT_4_0125_PREVIEW        = "gpt-4-0125-preview"
      GPT_4_1106_PREVIEW        = "gpt-4-1106-preview"
      GPT_4_VISION_PREVIEW      = "gpt-4-vision-preview"
      GPT_4_1106_VISION_PREVIEW = "gpt-4-1106-vision-preview"
      GPT_4                     = "gpt-4"
      GPT_4_0613                = "gpt-4-0613"
      GPT_4_32K                 = "gpt-4-32k"
      GPT_4_32K_0613            = "gpt-4-32k-0613"
      GPT_35_TURBO              = "gpt-3.5-turbo"
      GPT_35_TURBO_0125         = "gpt-3.5-turbo-0125"
      GPT_35_TURBO_1106         = "gpt-3.5-turbo-1106"
      GPT_35_TURBO_INSTRUCT     = "gpt-3.5-turbo-instruct"

      struct GaladrielExt
        getter fine_tune_api_key : String?

        def initialize(@fine_tune_api_key : String? = nil)
        end
      end

      struct GaladrielBuilder
        getter fine_tune_api_key : String?

        def initialize(@fine_tune_api_key : String? = nil)
        end
      end

      struct ClientBuilder
        getter api_key : String?
        getter base_url : String
        getter fine_tune_api_key : String?

        def initialize(
          @api_key : String? = nil,
          @base_url : String = GALADRIEL_API_BASE_URL,
          @fine_tune_api_key : String? = nil,
        )
        end

        def api_key(api_key : String) : self
          self.class.new(api_key, @base_url, @fine_tune_api_key)
        end

        def base_url(base_url : String) : self
          self.class.new(@api_key, base_url, @fine_tune_api_key)
        end

        def fine_tune_api_key(fine_tune_api_key : String) : self
          self.class.new(@api_key, @base_url, fine_tune_api_key)
        end

        def build : Client
          key = @api_key || raise "GALADRIEL_API_KEY not set"
          Client.new(key, @fine_tune_api_key, @base_url)
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
          if message = value.as_h["message"]?.try(&.as_s?)
            new(error: ApiErrorResponse.new(message))
          else
            new(ok: yield value)
          end
        end
      end

      struct Usage
        include JSON::Serializable

        @[JSON::Field(key: "prompt_tokens")]
        getter prompt_tokens : Int32
        @[JSON::Field(key: "total_tokens")]
        getter total_tokens : Int32

        def initialize(@prompt_tokens : Int32, @total_tokens : Int32)
        end
      end

      struct Function
        include JSON::Serializable

        getter name : String
        getter arguments : String

        def initialize(@name : String, @arguments : String)
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
        getter role : String
        getter content : String?
        getter tool_calls : Array(Crig::Providers::OpenAI::Chat::ToolCall)

        def initialize(
          @role : String,
          @content : String? = nil,
          @tool_calls : Array(Crig::Providers::OpenAI::Chat::ToolCall) = [] of Crig::Providers::OpenAI::Chat::ToolCall,
        )
        end

        def self.system(preamble : String) : self
          new("system", preamble)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["role"].as_s,
            hash["content"]?.try(&.as_s?),
            hash["tool_calls"]?.try(&.as_a?.try(&.map { |entry| Crig::Providers::OpenAI::Chat::ToolCall.from_json(entry.to_json) })) || [] of Crig::Providers::OpenAI::Chat::ToolCall,
          )
        end

        def self.from_core_message(message : Crig::Completion::Message) : self
          if message.role.user?
            content = message.content.to_a.find_map do |item|
              user_content = item.as(Crig::Completion::UserContent)
              if user_content.kind.text?
                user_content.text.try(&.text)
              end
            end
            return new("user", content)
          end

          text_content = nil
          tool_calls = [] of Crig::Providers::OpenAI::Chat::ToolCall
          message.content.each do |item|
            assistant_content = item.as(Crig::Completion::AssistantContent)
            case assistant_content.kind
            in .text?
              text = assistant_content.text.try(&.text) || ""
              text_content = text_content ? "#{text_content}\n#{text}" : text
            in .tool_call?
              tool_call = assistant_content.tool_call || raise Crig::Completion::CompletionError.new("Galadriel assistant tool call missing payload")
              tool_calls << Crig::Providers::OpenAI::Chat::ToolCall.from_core(tool_call)
            in .reasoning?
              raise Crig::Completion::MessageError.new("Galadriel currently doesn't support reasoning.")
            in .image?
              raise Crig::Completion::MessageError.new("Galadriel currently doesn't support images.")
            end
          end

          new("assistant", text_content, tool_calls)
        end

        def to_core_message : Crig::Completion::Message
          case @role
          when "user"
            text = @content || raise Crig::Completion::MessageError.new("Empty user message")
            Crig::Completion::Message.user(text)
          when "assistant"
            contents = [] of Crig::Completion::AssistantContent
            @tool_calls.each do |tool_call|
              contents << Crig::Completion::AssistantContent.tool_call(
                tool_call.id,
                tool_call.function.name,
                tool_call.function.arguments,
              )
            end
            if content = @content
              contents << Crig::Completion::AssistantContent.text(content)
            end
            raise Crig::Completion::MessageError.new("Empty assistant message") if contents.empty?

            Crig::Completion::Message.new(
              Crig::Completion::Message::Role::Assistant,
              Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(
                contents.map(&.as(Crig::Completion::UserContent | Crig::Completion::AssistantContent))
              ),
            )
          else
            raise Crig::Completion::MessageError.new("Unknown role: #{@role}")
          end
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "role", @role
            json.field "content", @content unless @content.nil?
            unless @tool_calls.empty?
              json.field "tool_calls" do
                json.array do
                  @tool_calls.each(&.to_json(json))
                end
              end
            end
          end
        end
      end

      struct Choice
        include JSON::Serializable

        getter index : Int32
        getter message : Message
        getter logprobs : JSON::Any?
        getter finish_reason : String

        def initialize(@index : Int32, @message : Message, @finish_reason : String, @logprobs : JSON::Any? = nil)
        end

        def self.new(pull : JSON::PullParser)
          from_json_value(JSON.parse(pull.read_raw))
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
        include JSON::Serializable

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

        def to_completion_response : Crig::Completion::CompletionResponse(self)
          choice = @choices.first? || raise Crig::Completion::CompletionError.new("Response contained no choices")
          message = choice.message

          content = [] of Crig::Completion::AssistantContent
          if text = message.content
            content << Crig::Completion::AssistantContent.text(text)
          end
          message.tool_calls.each do |call|
            content << Crig::Completion::AssistantContent.tool_call(
              call.function.name,
              call.function.name,
              call.function.arguments,
            )
          end
          raise Crig::Completion::CompletionError.new("Response contained no message or tool call (empty)") if content.empty?

          usage = if response_usage = @usage
                    Crig::Completion::Usage.new(
                      input_tokens: response_usage.prompt_tokens.to_i64,
                      output_tokens: (response_usage.total_tokens - response_usage.prompt_tokens).to_i64,
                      total_tokens: response_usage.total_tokens.to_i64,
                      cached_input_tokens: 0_i64,
                    )
                  else
                    Crig::Completion::Usage.new
                  end

          Crig::Completion::CompletionResponse(self).new(
            Crig::OneOrMany(Crig::Completion::AssistantContent).many(content),
            usage,
            self,
          )
        end
      end

      struct GaladrielCompletionRequest
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
            full_history << Message.from_core_message(message)
          end

          tool_choice = req.tool_choice.try do |choice|
            case choice.kind
            in .auto?     then Crig::Providers::OpenAI::Chat::ToolChoice::Auto
            in .none?     then Crig::Providers::OpenAI::Chat::ToolChoice::None
            in .required? then Crig::Providers::OpenAI::Chat::ToolChoice::Required
            in .specific?
              raise Crig::Completion::CompletionError.new("Galadriel does not support specific function tool choice")
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

      struct Client
        getter api_key : Crig::BearerAuth
        getter fine_tune_api_key : String?
        getter base_url : String

        def initialize(@api_key : Crig::BearerAuth, @fine_tune_api_key : String? = nil, @base_url : String = GALADRIEL_API_BASE_URL)
        end

        def self.new(api_key : String, fine_tune_api_key : String? = nil, base_url : String = GALADRIEL_API_BASE_URL) : self
          new(Crig::BearerAuth.new(api_key), fine_tune_api_key, base_url)
        end

        def self.builder : ClientBuilder
          ClientBuilder.new
        end

        def self.from_env : self
          api_key = ENV["GALADRIEL_API_KEY"]? || raise "GALADRIEL_API_KEY not set"
          new(api_key, ENV["GALADRIEL_FINE_TUNE_API_KEY"]?, GALADRIEL_API_BASE_URL)
        end

        def self.from_val(input : {String, String?}) : self
          new(input[0], input[1], GALADRIEL_API_BASE_URL)
        end

        def completion_model(model : String) : CompletionModel
          CompletionModel.new(self, model)
        end

        def post_json(path : String, body : String, accept : String = "application/json") : HTTP::Client::Response
          headers = HTTP::Headers{
            "Authorization" => "Bearer #{@api_key.token}",
            "Content-Type"  => "application/json",
            "Accept"        => accept,
          }
          if fine_tune_api_key = @fine_tune_api_key
            headers["X-Fine-Tune-Api-Key"] = fine_tune_api_key
          end
          HTTP::Client.exec("POST", build_uri(path), headers: headers, body: body)
        end

        def build_uri(path : String) : String
          "#{@base_url.rstrip('/')}/#{path.lstrip('/')}"
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
          span = Crig::Span.chat_span("galadriel", @model, request.preamble, nil)

          payload = GaladrielCompletionRequest.from_request(@model, request)
          response = @client.post_json("/chat/completions", payload.to_json)
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

          parsed = JSON.parse(body)
          envelope = ApiResponse(CompletionResponse).from_json_value(parsed) { |value| CompletionResponse.from_json(value.to_json) }
          if error = envelope.error
            raise Crig::Completion::CompletionError.new(error.message)
          end
          completion_response = envelope.ok || raise Crig::Completion::CompletionError.new("Galadriel response did not include a success payload")
          result = completion_response.to_completion_response
          if response = result.raw_response
            span.record_response_metadata(response) if response.responds_to?(:get_response_id)
            span.record_token_usage(result.usage) if result.usage.responds_to?(:token_usage)
          end
          span.end_span
          result
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          payload = GaladrielCompletionRequest.from_request(@model, request)
          merged = if params = payload.additional_params
                     JSON.parse(Crig::Providers::OpenAI.merge_json_hashes(params.as_h, JSON.parse(%({"stream":true,"stream_options":{"include_usage":true}})).as_h).to_json)
                   else
                     JSON.parse(%({"stream":true,"stream_options":{"include_usage":true}}))
                   end
          request_payload = GaladrielCompletionRequest.new(
            payload.model,
            payload.messages,
            payload.temperature,
            payload.tools,
            payload.tool_choice,
            merged,
          )
          response = @client.post_json("/chat/completions", request_payload.to_json, "text/event-stream")
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

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
            tool_call_chunks = choice.try(&.delta.tool_calls).try(&.map do |tool_call|
              Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk.new(
                tool_call.index, tool_call.id, tool_call.function.name, tool_call.function.arguments,
              )
            end) || [] of Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk

            compat_choice = Crig::Providers::Internal::OpenAICompatible::CompatibleChoice.new(
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

          def should_evict(existing : Crig::RawStreamingToolCall, incoming : Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk) : Bool
            false
          end

          def should_emit_completed_tool_call_immediately(tool_call : Crig::RawStreamingToolCall, incoming : Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk) : Bool
            false
          end
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end
      end

      struct Client
        include Crig::CompletionClient(Crig::Providers::Galadriel::CompletionModel)
      end
    end
  end
end
