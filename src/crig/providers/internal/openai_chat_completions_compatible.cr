module Crig
  module Providers
    module Internal
      # ameba:disable Lint/UnneededDisableDirective

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
            !!@name.try { |val| !val.empty? }
          end

          def has_nonempty_arguments? : Bool
            !!@arguments.try { |a| !a.empty? }
          end

          def starts_new_tool_call? : Bool
            has_nonempty_name? && (@arguments.nil? || !!@arguments.try(&.empty?))
          end

          # ameba:disable Naming/PredicateName
          def is_complete_single_chunk? : Bool
            has_nonempty_name? && has_nonempty_arguments?
          end
          # ameba:enable Naming/PredicateName
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
          return false if new_id.nil? || new_id.empty?
          return false if new_name.nil? || new_name.empty?
          return false if existing.id.empty?
          return false unless existing.id != new_id
          return false if existing.name.empty?

          existing.name != new_name || incoming.starts_new_tool_call?
        end

        def self.append_tool_call_arguments(tool_call : Crig::RawStreamingToolCall, chunk : String) : Crig::RawStreamingToolCall
          current_args = if tool_call.arguments.raw.nil?
                           ""
                         elsif (str = tool_call.arguments.as_s?)
                           if str.strip == "null" && !chunk.strip.empty?
                             ""
                           else
                             str
                           end
                         else
                           tool_call.arguments.to_json
                         end

          combined = current_args + chunk

          if combined.strip.starts_with?('{') && combined.strip.ends_with?('}')
            tool_call.arguments = JSON.parse(combined)
          else
            tool_call.arguments = JSON::Any.new(combined)
          end

          tool_call
        rescue
          tool_call.arguments = JSON::Any.new(combined)
          tool_call
        end

        def self.finalize_completed_streaming_tool_call(tool_call : Crig::RawStreamingToolCall) : Crig::RawStreamingToolCall
          if tool_call.arguments.raw.nil?
            tool_call.arguments = JSON::Any.new({} of String => JSON::Any)
          end
          tool_call
        end

        def self.finalize_pending_tool_call(tool_call : Crig::RawStreamingToolCall) : Crig::RawStreamingToolCall?
          return if tool_call.name.empty?

          if tool_call.arguments.raw.nil?
            tool_call.arguments = JSON::Any.new({} of String => JSON::Any)
            return tool_call
          end

          if (str = tool_call.arguments.as_s?)
            if str.strip.empty?
              tool_call.arguments = JSON::Any.new({} of String => JSON::Any)
              return tool_call
            end
            begin
              parsed = Crig::JSONUtils.parse_tool_arguments(str)
            rescue
              return nil
            end
            tool_call.arguments = parsed
            tool_call
          end

          tool_call
        end

        private def self.drain_finalized_tool_calls(
          tool_calls : Hash(Int32, Crig::RawStreamingToolCall),
        ) : Array(Crig::RawStreamingToolCall)
          completed = [] of Crig::RawStreamingToolCall
          pending = tool_calls.to_a.sort_by!(&.[0])
          tool_calls.clear

          pending.each do |_, tool_call|
            if finalized = finalize_pending_tool_call(tool_call)
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

        # Intermediate items produced by the SSE stream processor.  Callers
        # convert these to their specific RawStreamingChoice(T) variant.
        struct StreamItem
          getter message_id : String?
          getter text : String?
          getter reasoning : String?
          getter tool_call_delta_id : String?
          getter tool_call_delta_internal_id : String?
          getter tool_call_delta_content : Crig::ToolCallDeltaContent?
          getter tool_call : Crig::RawStreamingToolCall?

          def initialize(
            @message_id : String? = nil,
            @text : String? = nil,
            @reasoning : String? = nil,
            @tool_call_delta_id : String? = nil,
            @tool_call_delta_internal_id : String? = nil,
            @tool_call_delta_content : Crig::ToolCallDeltaContent? = nil,
            @tool_call : Crig::RawStreamingToolCall? = nil,
          )
          end
        end

        # Common SSE stream processor shared by all OpenAI Chat Completions-compatible
        # providers.  Each provider supplies a profile with normalize_chunk and
        # build_final_response callables to handle provider-specific chunk parsing.
        #
        # Returns an array of intermediate StreamItems plus the accumulated usage
        # value.  Callers convert StreamItems to their concrete RawStreamingChoice(T)
        # and append build_final_response(usage) as the final response.
        # ameba:disable Metrics/CyclomaticComplexity
        def self.process_compatible_sse_stream(
          text : String,
          profile,
        )
          items = [] of StreamItem
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
                items << StreamItem.new(message_id: rid)
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
                  items << StreamItem.new(tool_call: finalized)
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
                items << StreamItem.new(
                  tool_call_delta_id: existing_tc.id,
                  tool_call_delta_internal_id: existing_tc.id.empty? ? incoming.index.to_s : existing_tc.id,
                  tool_call_delta_content: Crig::ToolCallDeltaContent.name(name),
                )
              end

              if (arguments = incoming.arguments) && !arguments.empty?
                existing_tc = OpenAICompatible.append_tool_call_arguments(existing_tc, arguments)
                internal_id = existing_tc.id.empty? ? incoming.index.to_s : existing_tc.id
                items << StreamItem.new(
                  tool_call_delta_id: existing_tc.id,
                  tool_call_delta_internal_id: internal_id,
                  tool_call_delta_content: Crig::ToolCallDeltaContent.delta(arguments),
                )
              end

              tool_calls[incoming.index] = existing_tc

              if profile.should_emit_completed_tool_call_immediately(existing_tc, incoming)
                tool_calls.delete(incoming.index)
                items << StreamItem.new(tool_call: existing_tc)
              end
            end

            if profile.responds_to?(:decorate_tool_call)
              profile.decorate_tool_call(choice.tool_calls, tool_calls)
            end

            if (reasoning = choice.reasoning) && !reasoning.empty?
              items << StreamItem.new(reasoning: reasoning)
            end

            if (text = choice.text) && !text.empty?
              items << StreamItem.new(text: text)
            end

            if choice.finish_reason.tool_calls?
              OpenAICompatible.take_finalized_tool_calls(tool_calls).each do |finalized|
                items << StreamItem.new(tool_call: finalized)
              end
            end
          end

          OpenAICompatible.take_finalized_tool_calls(tool_calls).each do |finalized|
            items << StreamItem.new(tool_call: finalized)
          end

          {items, final_usage}
        end

        # Convert a StreamItem into a RawStreamingChoice(T).  Callers use
        # raw_choices = items.map { |item| OpenAICompatible.convert(item) }
        def self.convert_to_raw_choice(item : StreamItem, return_type : T.class) : Crig::RawStreamingChoice(T) forall T
          if mid = item.message_id
            Crig::RawStreamingChoice(T).message_id(mid)
          elsif content = item.text
            Crig::RawStreamingChoice(T).message(content)
          elsif content = item.reasoning
            Crig::RawStreamingChoice(T).reasoning_delta(nil, content)
          elsif content = item.tool_call_delta_content
            Crig::RawStreamingChoice(T).tool_call_delta(
              item.tool_call_delta_id || "",
              item.tool_call_delta_internal_id || "",
              content,
            )
          elsif tc = item.tool_call
            Crig::RawStreamingChoice(T).tool_call(tc)
          else
            Crig::RawStreamingChoice(T).message("")
          end
        end
      end
    end
  end
end
