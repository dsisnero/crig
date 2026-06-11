require "random/secure"

module Crig
  module Providers
    module Anthropic
      enum StreamingEventKind
        MessageStart
        ContentBlockStart
        ContentBlockDelta
        ContentBlockStop
        MessageDelta
        MessageStop
        Ping
        Unknown
      end

      struct MessageStart
        getter id : String
        getter role : String
        getter content : Array(Content)
        getter model : String
        getter stop_reason : String?
        getter stop_sequence : String?
        getter usage : Usage

        def initialize(
          @id : String,
          @role : String,
          @content : Array(Content),
          @model : String,
          @usage : Usage,
          @stop_reason : String? = nil,
          @stop_sequence : String? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(
            hash["id"].as_s,
            hash["role"].as_s,
            hash["content"].as_a.map { |entry| Content.from_json_value(entry) },
            hash["model"].as_s,
            Usage.from_json(hash["usage"].to_json),
            hash["stop_reason"]?.try(&.as_s?),
            hash["stop_sequence"]?.try(&.as_s?),
          )
        end
      end

      enum ContentDeltaKind
        TextDelta
        InputJsonDelta
        ThinkingDelta
        SignatureDelta
        CitationsDelta
        Unknown
      end

      struct ContentDelta
        getter kind : ContentDeltaKind
        getter text : String?
        getter citation : Citation?
        getter partial_json : String?
        getter thinking : String?
        getter signature : String?

        def initialize(
          @kind : ContentDeltaKind,
          @text : String? = nil,
          @partial_json : String? = nil,
          @thinking : String? = nil,
          @signature : String? = nil,
          @citation : Citation? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["type"].as_s
          when "text_delta"
            new(ContentDeltaKind::TextDelta, text: hash["text"].as_s)
          when "input_json_delta"
            new(ContentDeltaKind::InputJsonDelta, partial_json: hash["partial_json"].as_s)
          when "thinking_delta"
            new(ContentDeltaKind::ThinkingDelta, thinking: hash["thinking"].as_s)
          when "signature_delta"
            new(ContentDeltaKind::SignatureDelta, signature: hash["signature"].as_s)
          when "citations_delta"
            citation = Citation.from_json(hash["citation"].to_json)
            new(ContentDeltaKind::CitationsDelta, citation: citation)
          else
            new(ContentDeltaKind::Unknown)
          end
        end
      end

      struct MessageDelta
        getter stop_reason : String?
        getter stop_sequence : String?

        def initialize(@stop_reason : String? = nil, @stop_sequence : String? = nil)
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          new(hash["stop_reason"]?.try(&.as_s?), hash["stop_sequence"]?.try(&.as_s?))
        end
      end

      struct PartialUsage
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter output_tokens : Int64
        getter input_tokens : Int64?

        def initialize(@output_tokens : Int64 = 0_i64, @input_tokens : Int64? = nil)
        end

        def token_usage : Crig::Completion::Usage?
          input = @input_tokens || 0_i64
          Crig::Completion::Usage.new(input, @output_tokens, input + @output_tokens, 0_i64)
        end
      end

      struct StreamingEvent
        getter kind : StreamingEventKind
        getter message : MessageStart?
        getter index : Int32?
        getter content_block : Content?
        getter delta : ContentDelta?
        getter message_delta : MessageDelta?
        getter usage : PartialUsage?

        def initialize(
          @kind : StreamingEventKind,
          @message : MessageStart? = nil,
          @index : Int32? = nil,
          @content_block : Content? = nil,
          @delta : ContentDelta? = nil,
          @message_delta : MessageDelta? = nil,
          @usage : PartialUsage? = nil,
        )
        end

        def self.from_json_value(value : JSON::Any) : self
          hash = value.as_h
          case hash["type"].as_s
          when "message_start"
            new(StreamingEventKind::MessageStart, message: MessageStart.from_json_value(hash["message"]))
          when "content_block_start"
            new(
              StreamingEventKind::ContentBlockStart,
              index: hash["index"].as_i,
              content_block: Content.from_json_value(hash["content_block"]),
            )
          when "content_block_delta"
            new(
              StreamingEventKind::ContentBlockDelta,
              index: hash["index"].as_i,
              delta: ContentDelta.from_json_value(hash["delta"]),
            )
          when "content_block_stop"
            new(StreamingEventKind::ContentBlockStop, index: hash["index"].as_i)
          when "message_delta"
            new(
              StreamingEventKind::MessageDelta,
              message_delta: MessageDelta.from_json_value(hash["delta"]),
              usage: PartialUsage.from_json(hash["usage"].to_json),
            )
          when "message_stop"
            new(StreamingEventKind::MessageStop)
          when "ping"
            new(StreamingEventKind::Ping)
          else
            new(StreamingEventKind::Unknown)
          end
        end
      end

      struct ToolCallState
        property name : String
        property id : String
        property internal_call_id : String
        property input_json : String

        def initialize(
          @name : String = "",
          @id : String = "",
          @internal_call_id : String = "",
          @input_json : String = "",
        )
        end
      end

      struct ThinkingState
        property thinking : String
        property signature : String

        def initialize(@thinking : String = "", @signature : String = "")
        end
      end

      struct StreamingCompletionResponse
        include JSON::Serializable
        include Crig::Completion::GetTokenUsage

        getter usage : PartialUsage

        def initialize(@usage : PartialUsage = PartialUsage.new)
        end

        def token_usage : Crig::Completion::Usage?
          @usage.token_usage
        end
      end

      # ameba:disable Metrics/CyclomaticComplexity
      def self.handle_event(
        event : StreamingEvent,
        current_tool_call : ToolCallState?,
        current_thinking : ThinkingState?,
      ) : {Crig::RawStreamingChoice(StreamingCompletionResponse)?, ToolCallState?, ThinkingState?}
        result = case event.kind
                 when StreamingEventKind::ContentBlockDelta
                   delta = event.delta || raise Crig::Completion::CompletionError.new("Missing Anthropic content delta")
                   case delta.kind
                   when ContentDeltaKind::TextDelta
                     if current_tool_call.nil?
                       {
                         Crig::RawStreamingChoice(StreamingCompletionResponse).message(delta.text || ""),
                         current_tool_call,
                         current_thinking,
                       }
                     else
                       {nil, current_tool_call, current_thinking}
                     end
                   when ContentDeltaKind::InputJsonDelta
                     if tool_call = current_tool_call
                       tool_call.input_json += delta.partial_json || ""
                       {
                         Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call_delta(
                           tool_call.id,
                           tool_call.internal_call_id,
                           Crig::ToolCallDeltaContent.delta(delta.partial_json || ""),
                         ),
                         tool_call,
                         current_thinking,
                       }
                     else
                       {nil, current_tool_call, current_thinking}
                     end
                   when ContentDeltaKind::ThinkingDelta
                     thinking_state = current_thinking || ThinkingState.new
                     thinking_state.thinking += delta.thinking || ""
                     {
                       Crig::RawStreamingChoice(StreamingCompletionResponse).reasoning_delta(nil, delta.thinking || ""),
                       current_tool_call,
                       thinking_state,
                     }
                   when ContentDeltaKind::SignatureDelta
                     thinking_state = current_thinking || ThinkingState.new
                     thinking_state.signature += delta.signature || ""
                     {nil, current_tool_call, thinking_state}
                   end
                 when StreamingEventKind::ContentBlockStart
                   content_block = event.content_block || raise Crig::Completion::CompletionError.new("Missing Anthropic content block")
                   case content_block.kind
                   when Content::Kind::ToolUse
                     id = content_block.id || raise Crig::Completion::CompletionError.new("Missing Anthropic tool use id")
                     name = content_block.name || raise Crig::Completion::CompletionError.new("Missing Anthropic tool use name")
                     internal_call_id = Random::Secure.hex(8)
                     tool_call = ToolCallState.new(name, id, internal_call_id, "")
                     {
                       Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call_delta(
                         id,
                         internal_call_id,
                         Crig::ToolCallDeltaContent.name(name),
                       ),
                       tool_call,
                       current_thinking,
                     }
                   when Content::Kind::Thinking
                     {nil, current_tool_call, ThinkingState.new}
                   when Content::Kind::RedactedThinking
                     {
                       Crig::RawStreamingChoice(StreamingCompletionResponse).reasoning(
                         nil,
                         Crig::Completion::ReasoningContent.redacted(content_block.data || ""),
                       ),
                       current_tool_call,
                       current_thinking,
                     }
                   else
                     {nil, current_tool_call, current_thinking}
                   end
                 when StreamingEventKind::ContentBlockStop
                   if thinking_state = current_thinking
                     unless thinking_state.thinking.empty?
                       signature = thinking_state.signature.empty? ? nil : thinking_state.signature
                       return {
                         Crig::RawStreamingChoice(StreamingCompletionResponse).reasoning(
                           nil,
                           Crig::Completion::ReasoningContent.text(thinking_state.thinking, signature),
                         ),
                         current_tool_call,
                         nil,
                       }
                     end
                   end

                   if tool_call = current_tool_call
                     json_str = tool_call.input_json.empty? ? "{}" : tool_call.input_json
                     arguments = JSON.parse(json_str)
                     return {
                       Crig::RawStreamingChoice(StreamingCompletionResponse).tool_call(
                         Crig::RawStreamingToolCall.new(
                           tool_call.id,
                           tool_call.name,
                           arguments,
                         ).with_internal_call_id(tool_call.internal_call_id)
                       ),
                       nil,
                       current_thinking,
                     }
                   end

                   {nil, current_tool_call, current_thinking}
                 else
                   {nil, current_tool_call, current_thinking}
                 end
        result || {nil, current_tool_call, current_thinking}
      end

      # ameba:enable Metrics/CyclomaticComplexity

      def self.parse_sse_events(text : String) : Array(StreamingEvent)
        Decoders::SSEDecoder.iter_sse_messages([text.to_slice]).compact_map do |event|
          next if event.data == "[DONE]"
          StreamingEvent.from_json_value(JSON.parse(event.data))
        end
      end

      struct CompletionModel
        # ameba:disable Metrics/CyclomaticComplexity
        def stream(request : Crig::Completion::Request::CompletionRequest)
          request = if request.max_tokens.nil?
                      if max_tokens = @default_max_tokens
                        Crig::Completion::Request::CompletionRequest.new(
                          request.chat_history,
                          model: request.model,
                          preamble: request.preamble,
                          documents: request.documents,
                          tools: request.tools,
                          temperature: request.temperature,
                          max_tokens: max_tokens,
                          tool_choice: request.tool_choice,
                          additional_params: request.additional_params,
                          output_schema: request.output_schema,
                        )
                      else
                        raise Crig::Completion::CompletionError.new("`max_tokens` must be set for Anthropic")
                      end
                    else
                      request
                    end

          payload = AnthropicCompletionRequest.from_params(
            AnthropicRequestParams.new(@model, request, @prompt_caching)
          ).to_json_value

          stream_payload = payload.as_h.dup
          stream_payload["stream"] = JSON::Any.new(true)

          if !request.tools.empty? && !stream_payload.has_key?("tool_choice")
            stream_payload["tool_choice"] = Crig::Providers::OpenAI.build_json_any do |json|
              ToolChoice.auto.to_json(json)
            end
          end

          response = @client.post_json("/v1/messages", JSON.parse(stream_payload.to_json).to_json)
          body = response.body
          raise Crig::Completion::CompletionError.new(body) if response.status_code >= 400

          raw_choices = [] of Crig::RawStreamingChoice(StreamingCompletionResponse)
          current_tool_call = nil.as(ToolCallState?)
          current_thinking = nil.as(ThinkingState?)
          input_tokens = 0_i64
          final_usage = PartialUsage.new

          Anthropic.parse_sse_events(body).each do |event|
            case event.kind
            when StreamingEventKind::MessageStart
              message = event.message || raise Crig::Completion::CompletionError.new("Missing Anthropic message start")
              input_tokens = message.usage.input_tokens
              raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).message_id(message.id)
            when StreamingEventKind::MessageDelta
              delta = event.message_delta || raise Crig::Completion::CompletionError.new("Missing Anthropic message delta")
              usage = event.usage || PartialUsage.new
              if delta.stop_reason
                final_usage = PartialUsage.new(usage.output_tokens, input_tokens)
              end
            end

            choice, current_tool_call, current_thinking = Anthropic.handle_event(event, current_tool_call, current_thinking)
            raw_choices << choice if choice
          end

          raw_choices << Crig::RawStreamingChoice(StreamingCompletionResponse).final_response(
            StreamingCompletionResponse.new(final_usage)
          )

          Crig::StreamingCompletionResponse(StreamingCompletionResponse).stream_raw_choices(raw_choices)
        end
        # ameba:enable Metrics/CyclomaticComplexity
      end
    end
  end
end
