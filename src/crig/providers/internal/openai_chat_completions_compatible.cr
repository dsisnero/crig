module Crig
  module Providers
    module Internal
      module OpenAICompatible
        enum CompatibleFinishReason
          ToolCalls
          Other
        end

        struct CompatibleToolCallChunk
          getter index : Int32
          getter id : String?
          getter name : String?
          getter arguments : String?

          def initialize(@index : Int32, @id : String? = nil, @name : String? = nil, @arguments : String? = nil)
          end

          def has_nonempty_name? : Bool
            !!@name.try { |n| !n.empty? }
          end

          def has_nonempty_arguments? : Bool
            !!@arguments.try { |a| !a.empty? }
          end

          def starts_new_tool_call? : Bool
            has_nonempty_name? && (@arguments.nil? || @arguments.try(&.empty?))
          end

          def is_complete_single_chunk? : Bool
            has_nonempty_name? && has_nonempty_arguments?
          end
        end

        struct CompatibleChoice
          getter finish_reason : CompatibleFinishReason
          getter text : String?
          getter reasoning : String?
          getter tool_calls : Array(CompatibleToolCallChunk)

          def initialize(
            @finish_reason : CompatibleFinishReason = CompatibleFinishReason::Other,
            @text : String? = nil,
            @reasoning : String? = nil,
            @tool_calls : Array(CompatibleToolCallChunk) = [] of CompatibleToolCallChunk,
          )
          end
        end

        struct CompatibleChunk(U)
          getter response_id : String?
          getter response_model : String?
          getter choice : CompatibleChoice?
          getter usage : U?

          def initialize(
            @response_id : String? = nil,
            @response_model : String? = nil,
            @choice : CompatibleChoice? = nil,
            @usage : U? = nil,
          )
          end
        end

        def self.should_evict_distinct_named_tool_call(
          existing : Crig::RawStreamingToolCall,
          incoming : CompatibleToolCallChunk,
        ) : Bool
          new_id = incoming.id
          new_name = incoming.name
          return false unless new_id && !new_id.empty?
          return false unless new_name && !new_name.empty?
          return false if existing.id.empty?
          return false unless existing.id != new_id
          return false if existing.name.empty?

          existing.name != new_name || incoming.starts_new_tool_call?
        end

        def self.append_tool_call_arguments(tool_call : Crig::RawStreamingToolCall, chunk : String) : Nil
          current_args = case arg = tool_call.arguments
                         when .null?
                           ""
                         when .string?
                           str = arg.as_s
                           if str.strip == "null" && !chunk.strip.empty?
                             ""
                           else
                             str
                           end
                         else
                           arg.to_json
                         end

          combined = current_args + chunk

          if combined.strip.starts_with?('{') && combined.strip.ends_with?('}')
            tool_call.arguments = JSON.parse(combined)
          else
            tool_call.arguments = JSON::Any.new(combined)
          end
        rescue
          tool_call.arguments = JSON::Any.new(combined)
        end

        def self.finalize_completed_streaming_tool_call(tool_call : Crig::RawStreamingToolCall) : Crig::RawStreamingToolCall
          if tool_call.arguments.null?
            tool_call.arguments = JSON::Any.new({} of String => JSON::Any)
          end
          tool_call
        end

        def self.finalize_pending_tool_call(tool_call : Crig::RawStreamingToolCall) : Crig::RawStreamingToolCall?
          return nil if tool_call.name.empty?

          case arg = tool_call.arguments
          when .null?
            tool_call.arguments = JSON::Any.new({} of String => JSON::Any)
            return tool_call
          when .string?
            str = arg.as_s
            if str.strip.empty?
              tool_call.arguments = JSON::Any.new({} of String => JSON::Any)
              return tool_call
            end
            parsed = Crig::JSONUtils.parse_tool_arguments(str)
            return nil unless parsed
            tool_call.arguments = parsed
            return tool_call
          else
            return tool_call
          end
        end

        private def self.drain_finalized_tool_calls(
          tool_calls : Hash(Int32, Crig::RawStreamingToolCall),
        ) : Array(Crig::RawStreamingToolCall)
          completed = [] of Crig::RawStreamingToolCall
          pending = tool_calls.to_a.sort_by!(&.[0])
          tool_calls.clear

          pending.each do |_, tc|
            if finalized = finalize_pending_tool_call(tc)
              completed << finalized
            end
          end

          completed
        end

        def self.take_finalized_tool_calls(
          tool_calls : Hash(Int32, Crig::RawStreamingToolCall),
        ) : Array(Crig::RawStreamingToolCall)
          drain_finalized_tool_calls(tool_calls)
        end

        # Common SSE stream processor shared by all OpenAI Chat Completions-compatible
        # providers. Each provider supplies a profile with normalize_chunk and
        # build_final_response callables to handle provider-specific chunk parsing.
        #
        # Process an SSE text body line by line, accumulating tool calls via the
        # shared state machine, and return an array of RawStreamingChoice items plus
        # the final response. Callers wrap these with
        # StreamingCompletionResponse(R).stream_raw_choices(raw_choices) after
        # appending the final response.
        def self.process_compatible_sse_stream(
          text : String,
          profile,
        ) : {Array(Crig::RawStreamingChoice(T)), T} forall T
          raw_choices = [] of Crig::RawStreamingChoice(T)
          tool_calls = Hash(Int32, Crig::RawStreamingToolCall).new
          final_usage = nil
          seen_response_id = false

          text.each_line do |line|
            stripped = line.strip
            next if stripped.empty?
            next unless stripped.starts_with?("data:")
            data = stripped.lchop("data:").strip
            next if data.empty? || data == "[DONE]"

            chunk = begin
              profile.normalize_chunk(data)
            rescue error : Exception
              break
            end

            next unless chunk

            if rid = chunk.response_id
              unless seen_response_id
                seen_response_id = true
                raw_choices << Crig::RawStreamingChoice(T).message_id(rid)
              end
            end

            if usage = chunk.usage
              final_usage = usage
              next unless chunk.choice
            end

            choice = chunk.choice
            next unless choice

            choice.tool_calls.each do |incoming|
              if (existing = tool_calls[incoming.index]?) &&
                 profile.should_evict(existing, incoming)
                if evicted = tool_calls.delete(incoming.index)
                  finalized = OpenAICompatible.finalize_completed_streaming_tool_call(evicted)
                  raw_choices << Crig::RawStreamingChoice(T).tool_call(finalized)
                end
              end

              existing_tc = tool_calls[incoming.index]? || begin
                tc = Crig::RawStreamingToolCall.empty
                tool_calls[incoming.index] = tc
                tc
              end

              if (id = incoming.id) && !id.empty?
                existing_tc.id = id
              end

              if (name = incoming.name) && !name.empty?
                existing_tc.name = name
                raw_choices << Crig::RawStreamingChoice(T).tool_call_delta(
                  existing_tc.id,
                  existing_tc.id.empty? ? incoming.index.to_s : existing_tc.id,
                  Crig::ToolCallDeltaContent.name(name),
                )
              end

              if (arguments = incoming.arguments) && !arguments.empty?
                OpenAICompatible.append_tool_call_arguments(existing_tc, arguments)
                internal_id = existing_tc.id.empty? ? incoming.index.to_s : existing_tc.id
                raw_choices << Crig::RawStreamingChoice(T).tool_call_delta(
                  existing_tc.id,
                  internal_id,
                  Crig::ToolCallDeltaContent.delta(arguments),
                )
              end

              if profile.should_emit_completed_tool_call_immediately(existing_tc, incoming)
                tool_calls.delete(incoming.index)
                raw_choices << Crig::RawStreamingChoice(T).tool_call(existing_tc)
              end
            end

            if profile.responds_to?(:decorate_tool_call)
              profile.decorate_tool_call(choice.tool_calls, tool_calls)
            end

            if (reasoning = choice.reasoning) && !reasoning.empty?
              raw_choices << Crig::RawStreamingChoice(T).reasoning_delta(nil, reasoning)
            end

            if (text = choice.text) && !text.empty?
              raw_choices << Crig::RawStreamingChoice(T).message(text)
            end

            if choice.finish_reason.tool_calls?
              OpenAICompatible.take_finalized_tool_calls(tool_calls).each do |tc|
                raw_choices << Crig::RawStreamingChoice(T).tool_call(tc)
              end
            end
          end

          OpenAICompatible.take_finalized_tool_calls(tool_calls).each do |tc|
            raw_choices << Crig::RawStreamingChoice(T).tool_call(tc)
          end

          final_response = profile.build_final_response(final_usage)

          {raw_choices, final_response}
        end
      end
    end
  end
end
