module Crig
  module Providers
    module Doubleword
      QWEN3_5_4B        = "Qwen/Qwen3.5-4B"
      QWEN3_5_9B        = "Qwen/Qwen3.5-9B"
      QWEN3_5_397B_A17B = "Qwen/Qwen3.5-397B-A17B-FP8"
      QWEN3_6_35B_A3B   = "Qwen/Qwen3.6-35B-A3B-FP8"
      GPT_OSS_20B       = "openai/gpt-oss-20b"
      GPT_OSS_120B      = "openai/gpt-oss-120b"
      DEEPSEEK_V4_PRO   = "deepseek-ai/DeepSeek-V4-Pro"
      DEEPSEEK_V4_FLASH = "deepseek-ai/DeepSeek-V4-Flash"
      KIMI_K2_6         = "moonshotai/Kimi-K2.6"
      GLM_5_2           = "zai-org/GLM-5.2-FP8"
      QWEN3_VL_30B      = "Qwen/Qwen3-VL-30B-A3B-Instruct-FP8"
      QWEN3_VL_235B     = "Qwen/Qwen3-VL-235B-A22B-Instruct-FP8"

      struct DoublewordCompletionRequest
        getter model : String
        getter messages : Array(Crig::Providers::OpenAI::Chat::Message)
        getter temperature : Float64?
        getter tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition)
        getter tool_choice : Crig::Providers::OpenAI::Chat::ToolChoice?
        getter additional_params : JSON::Any?
        getter? stream : Bool

        def initialize(
          @model : String,
          @messages : Array(Crig::Providers::OpenAI::Chat::Message),
          @temperature : Float64? = nil,
          @tools : Array(Crig::Providers::OpenAI::Chat::ToolDefinition) = [] of Crig::Providers::OpenAI::Chat::ToolDefinition,
          @tool_choice : Crig::Providers::OpenAI::Chat::ToolChoice? = nil,
          @additional_params : JSON::Any? = nil,
          @stream : Bool = false,
        )
        end

        def self.from_request(default_model : String, req : Crig::Completion::Request::CompletionRequest) : self
          params = Crig::Providers::OpenAI::Chat::OpenAIRequestParams.new(
            req.model || default_model,
            req,
          )
          messages = Crig::Providers::OpenAI::Chat::CompletionRequest.from_openai_request_params(params).messages

          tool_choice = req.tool_choice.try do |choice|
            case choice.kind
            in .auto?     then Crig::Providers::OpenAI::Chat::ToolChoice::Auto
            in .none?     then Crig::Providers::OpenAI::Chat::ToolChoice::None
            in .required? then Crig::Providers::OpenAI::Chat::ToolChoice::Required
            in .specific?
              raise Crig::Completion::CompletionError.new("Doubleword does not support specific function tool choice")
            end
          end

          new(
            req.model || default_model,
            messages,
            req.temperature,
            req.tools.map { |tool| Crig::Providers::OpenAI::Chat::ToolDefinition.from_tool(tool) },
            tool_choice,
            req.additional_params,
            false,
          )
        end

        def to_json(json : JSON::Builder) : Nil
          json.object do
            json.field "model", @model
            json.field "messages" do
              json.array do
                @messages.each(&.to_json_value.to_json(json))
              end
            end
            json.field "temperature", @temperature unless @temperature.nil?
            unless @tools.empty?
              json.field "tools" do
                json.array do
                  @tools.each(&.to_json_value.to_json(json))
                end
              end
            end
            json.field "tool_choice", @tool_choice.try(&.to_wire) unless @tool_choice.nil?
            if additional_params = @additional_params
              additional_params.as_h.each do |key, value|
                json.field key, value
              end
            end
            json.field "stream", @stream
          end
        end
      end

      struct StreamingCompletionResponse
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter usage : Crig::Providers::OpenAI::OpenAIUsage

        def initialize(@usage : Crig::Providers::OpenAI::OpenAIUsage)
        end

        def token_usage : Crig::Completion::Usage?
          @usage.to_crig_usage
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
          payload = DoublewordCompletionRequest.from_request(@model, request)

          Crig::Providers::Internal::GenericCompletionModel.send_completion_request(
            @client,
            "/chat/completions",
            payload.to_json,
            "doubleword",
            @model,
            request.preamble,
          ) do |parsed|
            if err = parsed["error"]?.try(&.as_h?).try(&.["message"]?.try(&.as_s?))
              raise Crig::Completion::CompletionError.new(err)
            end
            envelope = ApiResponse(Crig::Providers::OpenAI::Chat::CompletionResponse).from_json_value(parsed) { |value| Crig::Providers::OpenAI::Chat::CompletionResponse.from_json_value(value) }
            completion_response = envelope.ok || raise Crig::Completion::CompletionError.new("Doubleword response did not include a success payload")
            completion_response.to_completion_response(parsed)
          end
        end

        def stream(request : Crig::Completion::Request::CompletionRequest)
          base = DoublewordCompletionRequest.from_request(@model, request)
          payload = DoublewordCompletionRequest.new(
            base.model,
            base.messages,
            base.temperature,
            base.tools,
            base.tool_choice,
            base.additional_params,
            true,
          )
          response = @client.post_json("/chat/completions", payload.to_json, "text/event-stream")
          body = response.body
          raise Crig::Completion::CompletionError.from_http_response(response.status_code, body) if response.status_code >= 400

          Crig::StreamingCompletionResponse(StreamingCompletionResponse).stream_raw_choices(parse_streaming_choices(body))
        end

        private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(StreamingCompletionResponse))
          raw_choices = [] of Crig::RawStreamingChoice(StreamingCompletionResponse)
          calls = {} of Int32 => {String, String, String}
          final_usage = Crig::Providers::OpenAI::OpenAIUsage.new

          text.each_line do |line|
            stripped = line.strip
            next if stripped.empty? || !stripped.starts_with?("data:")
            payload = stripped.lchop("data:").strip
            next if payload == "[DONE]"

            parsed = JSON.parse(payload)
            if usage = parsed["usage"]?
              final_usage = Crig::Providers::OpenAI::OpenAIUsage.from_json(usage.to_json)
            end

            choice = parsed["choices"]?.try(&.as_a?.try(&.first?))
            next unless choice
            delta = choice["delta"]?.try(&.as_h?) || next

            if content = delta["content"]?.try(&.as_s?)
              raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).message(content) unless content.empty?
            end

            tool_calls = delta["tool_calls"]?.try(&.as_a?) || [] of JSON::Any
            tool_calls.each do |entry|
              append_streaming_tool_call(raw_choices, calls, entry)
            end
          end

          calls.each_value do |(id, name, arguments)|
            parsed_arguments = parse_json_or_string(arguments)
            raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
              Crig::RawStreamingToolCall.new(id, name, parsed_arguments)
            )
          end

          raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).final_response(
            StreamingCompletionResponse.new(final_usage)
          )
          raw_choices
        end

        private def append_streaming_tool_call(
          raw_choices : Array(Crig::RawStreamingChoice(StreamingCompletionResponse)),
          calls : Hash(Int32, {String, String, String}),
          entry : JSON::Any,
        ) : Nil
          hash = entry.as_h
          index = hash["index"]?.try(&.as_i?) || 0
          id = hash["id"]?.try(&.as_s?) || ""
          function = hash["function"]?.try(&.as_h?) || {} of String => JSON::Any
          name = function["name"]?.try(&.as_s?) || ""
          arguments = function["arguments"]?.try(&.as_s?) || ""

          if !name.empty? && arguments.empty?
            calls[index] = {id, name, ""}
            return
          end

          if name.empty? && !arguments.empty?
            if existing = calls[index]?
              calls[index] = {existing[0], existing[1], existing[2] + arguments}
            end
            return
          end

          parsed_arguments = parse_json_or_string(arguments)
          raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
            Crig::RawStreamingToolCall.new(id, name, parsed_arguments)
          )
        end

        private def parse_json_or_string(value : String) : JSON::Any
          JSON.parse(value)
        rescue
          JSON::Any.new(value)
        end

        def into_agent_builder : Crig::AgentBuilder(self)
          Crig::AgentBuilder(self).new(self)
        end
      end
    end
  end
end
