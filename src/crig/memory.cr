module Crig
  module Memory
    # Errors produced by a ConversationMemory backend.
    class MemoryError < Exception
      enum Kind
        Backend
        Policy
        Internal
      end

      getter kind : Kind
      getter detail : String

      def initialize(@kind : Kind, message : String, @detail : String = "")
        super(message)
      end

      def self.backend(message : String, detail : String = "") : self
        new(Kind::Backend, message, detail)
      end

      def self.policy(message : String, detail : String = "") : self
        new(Kind::Policy, message, detail)
      end

      def self.internal(message : String, detail : String = "") : self
        new(Kind::Internal, message, detail)
      end
    end

    # A persistent conversation history backend.
    #
    # Implementors store an ordered list of Messages per conversation_id.
    # Rig invokes `load` before sending a prompt and `append` after a
    # successful turn.
    module ConversationMemory
      abstract def load(conversation_id : String) : Array(Crig::Completion::Message)
      abstract def append(conversation_id : String, messages : Array(Crig::Completion::Message)) : Nil
      abstract def clear(conversation_id : String) : Nil
    end

    # Type alias for a history-shaping closure applied during load.
    # Takes the full message list and returns a transformed list.
    alias MessageFilter = Proc(Array(Crig::Completion::Message), Array(Crig::Completion::Message))

    # A side-channel for messages that a memory policy or adapter removes
    # from active history during ConversationMemory#load.
    #
    # Hooks should be inexpensive: they run inline on every load that produces
    # demoted messages.
    module DemotionHook
      abstract def on_demote(conversation_id : String, messages : Array(Crig::Completion::Message)) : Nil
    end

    # A DemotionHook that does nothing. Useful as a default when an adapter
    # requires a hook value but the caller has no long-tail store wired up yet.
    struct NoopDemotionHook
      include DemotionHook

      def on_demote(conversation_id : String, messages : Array(Crig::Completion::Message)) : Nil
      end
    end

    # Derives a single Message-shaped artifact from a slice of messages that
    # a memory policy has evicted from the active window.
    #
    # Implementations typically wrap an LLM call or a pure template rollup.
    #
    # `carry_over` is the artifact produced by the previous compaction for
    # this conversation, if any. Implementations that want a recursive summary
    # should summarize `evicted` together with `carry_over`.
    module Compactor
      abstract def compact(
        conversation_id : String,
        evicted : Array(Crig::Completion::Message),
        carry_over : Crig::Completion::Message?,
      ) : Crig::Completion::Message
    end

    # A simple thread-safe in-memory ConversationMemory backed by a Hash.
    #
    # Messages are stored in process memory only and lost on restart.
    class InMemoryConversationMemory
      include ConversationMemory

      @store : Hash(String, Array(Crig::Completion::Message))
      @filter : MessageFilter?
      @mutex : ::Mutex

      def initialize
        @store = {} of String => Array(Crig::Completion::Message)
        @filter = nil
        @mutex = ::Mutex.new
      end

      # Apply a filter to the loaded message list on every load.
      def with_filter(filter : MessageFilter) : self
        @filter = filter
        self
      end

      # Load the full conversation history for conversation_id.
      # Returns an empty Array if the conversation has no stored messages.
      def load(conversation_id : String) : Array(Crig::Completion::Message)
        @mutex.synchronize do
          messages = @store[conversation_id]?.try(&.dup) || [] of Crig::Completion::Message
          if f = @filter
            f.call(messages)
          else
            messages
          end
        end
      end

      # Append messages to the conversation identified by conversation_id.
      def append(conversation_id : String, messages : Array(Crig::Completion::Message)) : Nil
        @mutex.synchronize do
          @store[conversation_id] ||= [] of Crig::Completion::Message
          @store[conversation_id].concat(messages)
        end
      end

      # Remove all stored messages for conversation_id.
      def clear(conversation_id : String) : Nil
        @mutex.synchronize do
          @store.delete(conversation_id)
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
        rescue
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
        rescue
          @mutex.synchronize do
            if entry = @state[conversation_id]?
              entry.in_flight = false
            end
          end
          return splice_summary(carry_over, kept)
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
