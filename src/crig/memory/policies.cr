module Crig
  module Memory
    module MemoryPolicy
      abstract def apply(messages : Array(Crig::Completion::Message)) : Array(Crig::Completion::Message)?

      def apply_with_demoted(messages : Array(Crig::Completion::Message)) : Tuple(Array(Crig::Completion::Message), Array(Crig::Completion::Message))
        kept = apply(messages) || messages
        {kept, [] of Crig::Completion::Message}
      end
    end

    struct NoopMemoryPolicy
      include MemoryPolicy

      def apply(messages : Array(Crig::Completion::Message)) : Array(Crig::Completion::Message)?
        messages
      end
    end

    struct SlidingWindowMemory
      include MemoryPolicy

      getter max_messages : Int32

      def initialize(@max_messages : Int32)
      end

      def self.last_messages(n : Int32) : self
        new(n)
      end

      def apply(messages : Array(Crig::Completion::Message)) : Array(Crig::Completion::Message)?
        apply_with_demoted(messages)[0]
      end

      def apply_with_demoted(messages : Array(Crig::Completion::Message)) : Tuple(Array(Crig::Completion::Message), Array(Crig::Completion::Message))
        return {messages, [] of Crig::Completion::Message} if messages.size <= @max_messages

        start = messages.size - @max_messages
        demoted = messages[0...start]
        window = messages[start..]

        if window.size > 0 && window[0].role.user?
          first_content = window[0].content.first?
          if first_content && first_content.as?(Crig::Completion::UserContent).try(&.kind.tool_result?)
            demoted << window[0]
            window = window[1..]
          end
        end

        {window, demoted}
      end
    end

    module TokenCounter
      abstract def count(message : Crig::Completion::Message) : Int32
    end

    struct HeuristicTokenCounter
      include TokenCounter

      getter bytes_per_token : Float64
      getter per_message_overhead : Int32
      getter per_attachment_tokens : Int32

      def initialize(
        @bytes_per_token : Float64 = 4.0,
        @per_message_overhead : Int32 = 4,
        @per_attachment_tokens : Int32 = 256,
      )
        @bytes_per_token = @bytes_per_token.nan? || @bytes_per_token < 1.0 ? 1.0 : @bytes_per_token
      end

      def self.openai : self
        new(4.0, 4, 256)
      end

      def self.anthropic : self
        new(3.5, 4, 256)
      end

      def self.gemini : self
        new(4.0, 4, 256)
      end

      def count(message : Crig::Completion::Message) : Int32
        tokens = case message.role
                 when .user?
                   message.content.sum { |c| count_user_content(c) }
                 when .assistant?
                   message.content.sum { |c| count_assistant_content(c.as(Crig::Completion::AssistantContent)) }
                 else
                   bytes_to_tokens(message.rag_text.try(&.bytesize) || 0)
                 end
        tokens + @per_message_overhead
      end

      private def bytes_to_tokens(bytes : Int32) : Int32
        ((bytes.to_f64) / @bytes_per_token).ceil.to_i
      end

      private def count_user_content(content : Crig::Completion::UserContent | Crig::Completion::AssistantContent) : Int32
        uc = content.as(Crig::Completion::UserContent)
        case uc.kind
        when .text?
          text_len = uc.text.try { |t| t.text.bytesize } || 0
          bytes_to_tokens(text_len)
        when .tool_result?
          result = uc.tool_result
          return @per_attachment_tokens unless result
          result.content.sum do |c|
            case c.kind
            when .text?
              text_len = c.text.try { |t| t.text.try(&.bytesize) } || 0
              bytes_to_tokens(text_len)
            else
              @per_attachment_tokens
            end
          end
        else
          @per_attachment_tokens
        end
      end

      private def count_assistant_content(content : Crig::Completion::AssistantContent) : Int32
        case content.kind
        when .text?
          text = content.text.try { |t| t.text } || ""
          bytes_to_tokens(text.bytesize)
        when .reasoning?
          reasoning = content.reasoning
          return @per_attachment_tokens unless reasoning
          text_len = reasoning.content.sum { |rc| (rc.summary.try(&.bytesize) || 0) + (rc.data.try(&.bytesize) || 0) }
          bytes_to_tokens(text_len)
        when .tool_call?
          call = content.tool_call
          return @per_attachment_tokens unless call
          args_json = call.function.arguments.to_json
          bytes_to_tokens(call.function.name.bytesize + args_json.bytesize)
        else
          @per_attachment_tokens
        end
      end
    end

    struct TokenWindowMemory
      include MemoryPolicy

      getter max_tokens : Int32
      getter counter : TokenCounter

      def initialize(@max_tokens : Int32, @counter : TokenCounter = HeuristicTokenCounter.new)
      end

      def apply(messages : Array(Crig::Completion::Message)) : Array(Crig::Completion::Message)?
        apply_with_demoted(messages)[0]
      end

      def apply_with_demoted(messages : Array(Crig::Completion::Message)) : Tuple(Array(Crig::Completion::Message), Array(Crig::Completion::Message))
        budget = @max_tokens
        keep_from = messages.size

        (messages.size - 1).downto(0) do |idx|
          cost = @counter.count(messages[idx])
          break if cost > budget
          budget -= cost
          keep_from = idx
        end

        demoted = messages[0...keep_from]
        kept = messages[keep_from..]? || [] of Crig::Completion::Message

        if kept.size > 0 && kept[0].role.user?
          first_content = kept[0].content.first?
          if first_content && first_content.as?(Crig::Completion::UserContent).try(&.kind.tool_result?)
            demoted = demoted + [kept[0]]
            kept = kept[1..]
          end
        end

        {kept, demoted}
      end
    end

    struct PolicyMemory(M, P)
      include ConversationMemory

      getter inner : M
      getter policy : P

      def initialize(@inner : M, @policy : P)
      end

      def load(conversation_id : String) : Array(Crig::Completion::Message)
        messages = @inner.load(conversation_id)
        @policy.apply(messages) || messages
      end

      def append(conversation_id : String, messages : Array(Crig::Completion::Message)) : Nil
        @inner.append(conversation_id, messages)
      end

      def clear(conversation_id : String) : Nil
        @inner.clear(conversation_id)
      end

      def into_inner : {M, P}
        {@inner, @policy}
      end
    end

    struct TemplateCompactor
      include Compactor

      getter header : String
      getter max_bytes : Int32?

      def initialize(
        @header : String = "[Conversation summary so far]",
        @max_bytes : Int32? = nil,
      )
      end

      def with_header(header : String) : self
        self.class.new(header, @max_bytes)
      end

      def with_max_bytes(max_bytes : Int32) : self
        self.class.new(@header, max_bytes == 0 ? nil : max_bytes)
      end

      def compact(
        conversation_id : String,
        evicted : Array(Crig::Completion::Message),
        carry_over : Crig::Completion::Message?,
      ) : Crig::Completion::Message
        buf = String.build do |io|
          io << @header << '\n'
          if prev = carry_over
            prev_text = prev.rag_text
            io << prev_text << '\n' if prev_text
          end
          evicted.each do |msg|
            line = render_message_line(msg)
            io << line << '\n' unless line.empty?
          end
        end

        if cap = @max_bytes
          buf = truncate_summary(buf, cap) if buf.bytesize > cap
        end

        Crig::Completion::Message.system(buf)
      end

      private def render_message_line(msg : Crig::Completion::Message) : String
        case msg.role
        when .user?
          io = IO::Memory.new
          msg.content.each do |c|
            uc = c.as?(Crig::Completion::UserContent)
            next unless uc
            case uc.kind
            when .text?
              val = uc.text.try(&.text)
              io << ' ' unless io.empty? || val.to_s.empty?
              io << val if val
            when .tool_result?
              io << ' ' unless io.empty?
              io << "[tool result]"
            else
              io << ' ' unless io.empty?
              io << "[attachment]"
            end
          end
          io.empty? ? "" : "user: #{io}"
        when .assistant?
          io = IO::Memory.new
          msg.content.each do |c|
            uc = c.as?(Crig::Completion::AssistantContent)
            next unless uc
            case uc.kind
            when .text?
              val = uc.text.try(&.text)
              io << ' ' unless io.empty? || val.to_s.empty?
              io << val if val
            when .tool_call?
              if tc = uc.tool_call
                io << ' ' unless io.empty?
                io << "[tool call: #{tc.function.name}]"
              end
            else
              io << ' ' unless io.empty?
              io << "[reasoning]"
            end
          end
          io.empty? ? "" : "assistant: #{io}"
        else
          text = msg.rag_text
          text && !text.empty? ? "system: #{text}" : ""
        end
      end

      private def truncate_summary(buf : String, cap : Int32) : String
        marker = "[\u{2026}truncated\u{2026}]\n"
        header_prefix_len = buf.index('\n').try { |i| i + 1 } || return buf

        return buf if buf.bytesize <= header_prefix_len

        preserved = header_prefix_len + marker.bytesize
        keep_bytes = cap - preserved
        return "#{buf[0...header_prefix_len]}#{marker}" if keep_bytes <= 0

        body_start = header_prefix_len
        body = buf.byte_slice(body_start)
        return buf unless body

        cut = body.bytesize - keep_bytes
        cut = 0 if cut < 0

        # Walk forward past UTF-8 continuation bytes (0x80-0xBF) to find
        # the next character boundary, matching Rust's is_char_boundary loop.
        while cut < body.bytesize
          byte = body.byte_at(cut)
          break unless byte && byte & 0xC0 == 0x80
          cut += 1
        end

        suffix = body.byte_slice(cut) || ""
        String.build do |io|
          io << buf[0...header_prefix_len]
          io << marker
          io << suffix
        end
      end
    end

    # Internal state for a single conversation tracked by DemotingPolicyMemory.
    private class ConversationDemotionState
      property delivered : Int32
      property in_flight : Bool

      def initialize
        @delivered = 0
        @in_flight = false
      end
    end

    # A ConversationMemory adapter that wraps a backend with a MemoryPolicy
    # and a DemotionHook. Messages truncated by the policy flow into the hook
    # before the active window is returned.
    #
    # Concurrent load calls on the same conversation_id are serialized: only
    # one call delivers to the hook at a time; others observe the existing
    # watermark and return immediately.
    class DemotingPolicyMemory(M, P, H)
      include ConversationMemory

      getter inner : M
      getter policy : P
      getter hook : H

      @state : Hash(String, ConversationDemotionState)
      @mutex : ::Mutex

      def initialize(@inner : M, @policy : P, @hook : H)
        @state = {} of String => ConversationDemotionState
        @mutex = ::Mutex.new
      end

      def load(conversation_id : String) : Array(Crig::Completion::Message)
        messages = @inner.load(conversation_id)
        kept, demoted = @policy.apply_with_demoted(messages)
        demoted_count = demoted.size

        pending = @mutex.synchronize do
          entry = @state[conversation_id]?
          if entry
            if entry.in_flight
              return kept
            end
            if entry.delivered >= demoted_count
              [] of Crig::Completion::Message
            else
              split = entry.delivered
              entry.in_flight = true
              demoted[split..]
            end
          elsif demoted_count == 0
            [] of Crig::Completion::Message
          else
            entry = ConversationDemotionState.new
            entry.in_flight = true
            @state[conversation_id] = entry
            demoted.dup
          end
        end

        return kept if pending.empty?

        begin
          @hook.on_demote(conversation_id, pending)
        rescue error
          @mutex.synchronize do
            if entry = @state[conversation_id]?
              entry.in_flight = false
            end
          end
          raise MemoryError.internal("demotion hook failed: #{error.message}")
        end

        @mutex.synchronize do
          if entry = @state[conversation_id]?
            entry.in_flight = false
            entry.delivered = demoted_count
          end
        end

        kept
      end

      def append(conversation_id : String, messages : Array(Crig::Completion::Message)) : Nil
        @inner.append(conversation_id, messages)
      end

      def clear(conversation_id : String) : Nil
        @inner.clear(conversation_id)
        @mutex.synchronize { @state.delete(conversation_id) }
      end

      def forget(conversation_id : String) : Nil
        @mutex.synchronize { @state.delete(conversation_id) }
      end

      def tracked_conversations : Int32
        @mutex.synchronize { @state.size }
      end

      def into_inner : {M, P, H}
        {@inner, @policy, @hook}
      end
    end

    # Internal state for a single conversation tracked by CompactingMemory.
    private class ConversationCompactionState
      property summary : Crig::Completion::Message?
      property absorbed : Int32
      property in_flight : Bool

      def initialize
        @summary = nil
        @absorbed = 0
        @in_flight = false
      end
    end

    # A ConversationMemory adapter that wraps a backend with a MemoryPolicy
    # and a Compactor, replacing truncated turns with a summary message spliced
    # at the front of the loaded history.
    #
    # The loaded history shape is [summary_message, ...kept_window] when any
    # compaction has occurred, or just kept_window otherwise. The summary is
    # recomputed on every load that produces newly-evicted messages, folding
    # older summaries into newer ones via the compactor's carry_over parameter.
    #
    # Concurrent load calls on the same conversation_id are serialized at the
    # compaction seam: only one call invokes the compactor at a time; others
    # observe the previously-stored summary and return immediately.
    class CompactingMemory(M, P, C)
      include ConversationMemory

      getter inner : M
      getter policy : P
      getter compactor : C

      @state : Hash(String, ConversationCompactionState)
      @mutex : ::Mutex

      def initialize(@inner : M, @policy : P, @compactor : C)
        @state = {} of String => ConversationCompactionState
        @mutex = ::Mutex.new
      end

      def load(conversation_id : String) : Array(Crig::Completion::Message)
        messages = @inner.load(conversation_id)
        kept, demoted = @policy.apply_with_demoted(messages)
        demoted_count = demoted.size

        plan = @mutex.synchronize do
          entry = @state[conversation_id]?
          if entry
            if entry.in_flight
              return splice_summary(entry.summary, kept)
            end
            if demoted_count <= entry.absorbed
              return splice_summary(entry.summary, kept)
            end
            entry.in_flight = true
            {entry.summary, entry.absorbed}
          elsif demoted_count == 0
            return kept
          else
            entry = ConversationCompactionState.new
            entry.in_flight = true
            @state[conversation_id] = entry
            {nil.as(Crig::Completion::Message?), 0}
          end
        end

        carry_over, skip = plan
        new_slice = demoted[skip..]
        return splice_summary(carry_over, kept) unless new_slice

        begin
          summary = @compactor.compact(conversation_id, new_slice, carry_over)
        rescue error
          @mutex.synchronize do
            if entry = @state[conversation_id]?
              entry.in_flight = false
            end
          end
          raise MemoryError.internal("compactor failed: #{error.message}")
        end

        @mutex.synchronize do
          if entry = @state[conversation_id]?
            entry.in_flight = false
            entry.absorbed = demoted_count
            entry.summary = summary
          end
        end

        splice_summary(summary, kept)
      end

      def append(conversation_id : String, messages : Array(Crig::Completion::Message)) : Nil
        @inner.append(conversation_id, messages)
      end

      def clear(conversation_id : String) : Nil
        @inner.clear(conversation_id)
        @mutex.synchronize { @state.delete(conversation_id) }
      end

      def forget(conversation_id : String) : Nil
        @mutex.synchronize { @state.delete(conversation_id) }
      end

      def tracked_conversations : Int32
        @mutex.synchronize { @state.size }
      end

      def into_inner : {M, P, C}
        {@inner, @policy, @compactor}
      end

      private def splice_summary(summary : Crig::Completion::Message?, kept : Array(Crig::Completion::Message)) : Array(Crig::Completion::Message)
        if s = summary
          [s] + kept
        else
          kept
        end
      end
    end
  end
end
