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
  end
end
