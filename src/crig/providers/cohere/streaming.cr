module Crig
  module Providers
    module Cohere
      module Streaming
        struct MessageContentDelta
          include JSON::Serializable

          getter text : String?
        end

        struct MessageToolFunctionDelta
          include JSON::Serializable

          getter name : String?
          getter arguments : String?
        end

        struct MessageToolCallDelta
          include JSON::Serializable

          getter id : String?
          getter function : MessageToolFunctionDelta?
        end

        struct MessageDelta
          include JSON::Serializable

          getter content : MessageContentDelta?
          getter tool_calls : MessageToolCallDelta?
        end

        struct Delta
          include JSON::Serializable

          getter message : MessageDelta?
        end

        struct MessageEndDelta
          include JSON::Serializable

          getter usage : Usage?
        end

        struct StreamingCompletionResponse
          include JSON::Serializable
          include Crig::Completion::GetTokenUsage

          getter usage : Usage?

          def initialize(@usage : Usage? = nil)
          end

          def token_usage : Crig::Completion::Usage?
            usage = @usage
            return unless usage

            tokens = usage.tokens
            input_tokens = tokens.try(&.input_tokens)
            output_tokens = tokens.try(&.output_tokens)
            return unless input_tokens && output_tokens

            Crig::Completion::Usage.new(
              input_tokens: input_tokens.to_i64,
              output_tokens: output_tokens.to_i64,
              total_tokens: input_tokens.to_i64 + output_tokens.to_i64,
            )
          end
        end

        struct StreamingEvent
          enum Kind
            MessageStart
            ContentStart
            ContentDelta
            ContentEnd
            ToolPlan
            ToolCallStart
            ToolCallDelta
            ToolCallEnd
            MessageEnd
          end

          getter kind : Kind
          getter delta : Delta?
          getter message_end_delta : MessageEndDelta?

          def initialize(@kind : Kind, @delta : Delta? = nil, @message_end_delta : MessageEndDelta? = nil)
          end

          def self.from_json_value(value : JSON::Any) : self
            hash = value.as_h
            case hash["type"].as_s
            when "message-start" then new(Kind::MessageStart)
            when "content-start" then new(Kind::ContentStart)
            when "content-delta" then new(Kind::ContentDelta, hash["delta"]?.try { |entry| Delta.from_json(entry.to_json) })
            when "content-end"   then new(Kind::ContentEnd)
            when "tool-plan"     then new(Kind::ToolPlan)
            when "tool-call-start"
              new(Kind::ToolCallStart, hash["delta"]?.try { |entry| Delta.from_json(entry.to_json) })
            when "tool-call-delta"
              new(Kind::ToolCallDelta, hash["delta"]?.try { |entry| Delta.from_json(entry.to_json) })
            when "tool-call-end" then new(Kind::ToolCallEnd)
            when "message-end"
              new(Kind::MessageEnd, nil, hash["delta"]?.try { |entry| MessageEndDelta.from_json(entry.to_json) })
            else
              raise Crig::Completion::CompletionError.new("Unknown Cohere streaming event type")
            end
          end
        end

        class StreamingCompletionResponseParser
          def initialize(@model : Crig::Providers::Cohere::CompletionModel)
          end

          def stream(request : Crig::Completion::Request::CompletionRequest)
            payload = CohereCompletionRequest.from_request(@model.model, request)
            params = if additional_params = payload.additional_params
                       Crig::Providers::OpenAI.merge_json_values(additional_params, JSON.parse(%({"stream":true})))
                     else
                       JSON.parse(%({"stream":true}))
                     end
            request_payload = CohereCompletionRequest.new(payload.model, payload.messages, payload.documents, payload.temperature, payload.tools, payload.tool_choice, params)
            response = @model.client.post_json("/v2/chat", request_payload.to_json_value.to_json)
            text = response.body
            raise Crig::Completion::CompletionError.new(text) if response.status_code >= 400
            Crig::Streaming::StreamingCompletionResponse(StreamingCompletionResponse).from_raw_choices(parse_streaming_choices(text))
          end

          private def parse_streaming_choices(text : String) : Array(Crig::RawStreamingChoice(StreamingCompletionResponse))
            raw_choices = [] of Crig::RawStreamingChoice(StreamingCompletionResponse)
            current_tool_call : {String, String, String, String}? = nil
            final_usage = nil.as(Usage?)

            text.each_line do |line|
              next unless line.starts_with?("data:")
              data_str = line[5..].to_s.strip
              next if data_str.empty? || data_str == "[DONE]"

              event = StreamingEvent.from_json_value(JSON.parse(data_str))
              case event.kind
              in .content_delta?
                content = event.delta.try(&.message).try(&.content)
                next unless text_delta = content.try(&.text)
                raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).message(text_delta)
              in .message_end?
                final_usage = event.message_end_delta.try(&.usage)
              in .tool_call_start?
                current_tool_call = parse_tool_call_start(event) || next
                raw_choices << tool_call_name_delta(current_tool_call)
              in .tool_call_delta?
                next unless current = current_tool_call
                function = event.delta.try(&.message).try(&.tool_calls).try(&.function)
                next unless arguments = function.try(&.arguments)
                current_tool_call = {current[0], current[1], current[2], "#{current[3]}#{arguments}"}
                raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call_delta(
                  current[0],
                  current[1],
                  Crig::ToolCallDeltaContent.delta(arguments),
                )
              in .tool_call_end?
                next unless current = current_tool_call
                arguments = JSON.parse(current[3])
                raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
                  Crig::RawStreamingToolCall.new(current[0], current[2], arguments, current[1])
                )
                current_tool_call = nil
              in .message_start?, .content_start?, .content_end?, .tool_plan?
              end
            end

            raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).final_response(
              StreamingCompletionResponse.new(final_usage)
            )
            raw_choices
          end

          private def parse_tool_call_start(event : StreamingEvent) : {String, String, String, String}?
            tool_call = event.delta.try(&.message).try(&.tool_calls)
            return unless tool_call
            id = tool_call.id
            function = tool_call.function
            return unless id && function
            name = function.name
            arguments = function.arguments
            return unless name && arguments
            {id, id, name, arguments}
          end

          private def tool_call_name_delta(current_tool_call : {String, String, String, String}) : Crig::RawStreamingChoice(StreamingCompletionResponse)
            Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call_delta(
              current_tool_call[0],
              current_tool_call[1],
              Crig::ToolCallDeltaContent.name(current_tool_call[2]),
            )
          end
        end
      end
    end
  end
end
