module Crig
  module Tool
    # A required typed value was missing from a ToolContext.
    class MissingToolContext < Exception
      getter type_name : String

      def initialize(@type_name : String)
        super("required tool context value of type `#{@type_name}` was not found")
      end
    end

    # Context passed to every tool execution.
    #
    # Callers insert typed inbound values with `#insert`. Tools read those
    # values with `#get` or `#require`, and attach host-only result metadata
    # with `#insert_result`. Result hooks inspect that metadata through
    # `#result`. Neither inbound values nor result metadata are sent to the
    # model.
    #
    # Dispatch clones inbound values once per call. Map-level mutations
    # (inserting, replacing, or removing typed slots) affect only that
    # execution.
    class ToolContext
      @inbound : Hash(String, String)?
      @result : Hash(String, String)?

      def initialize
      end

      # Internal: construct with pre-populated inbound map.
      def initialize_with_inbound(@inbound : Hash(String, String)?)
      end

      # -- Inbound --

      # Insert an inbound typed value, returning the displaced value if present.
      def insert(val : T) : T? forall T
        key = {{ T.name.stringify }}
        map = @inbound ||= {} of String => String
        prev_json = map[key]?
        map[key] = val.to_json
        prev_json.try { |j| T.from_json(j) }
      end

      # Read an inbound typed value.
      def get(type : T.class) : T? forall T
        map = @inbound
        return unless map
        json = map[{{ T.name.stringify }}]?
        json.try { |j| T.from_json(j) }
      end

      # Require an inbound typed value, raising MissingToolContext if absent.
      def require(type : T.class) : T forall T
        val = get(T)
        val || raise MissingToolContext.new({{ T.name.stringify }})
      end

      # Mutably access an inbound typed value.
      def get_mut(type : T.class) : T? forall T
        get(T)
      end

      # Remove an inbound typed value.
      def remove(type : T.class) : T? forall T
        map = @inbound
        return unless map
        key = {{ T.name.stringify }}
        json = map.delete(key)
        @inbound = nil if map.empty?
        json.try { |j| T.from_json(j) }
      end

      # Whether this context contains the inbound type T.
      def contains?(type : T.class) : Bool forall T
        !!(@inbound.try(&.has_key?({{ T.name.stringify }})))
      end

      def size : Int32
        @inbound.try(&.size) || 0
      end

      def empty? : Bool
        size == 0
      end

      # -- Result metadata --

      # Attach host-only metadata to this execution's result.
      def insert_result(val : T) : T? forall T
        key = {{ T.name.stringify }}
        map = @result ||= {} of String => String
        prev_json = map[key]?
        map[key] = val.to_json
        prev_json.try { |j| T.from_json(j) }
      end

      # Read host-only result metadata.
      def result(type : T.class) : T? forall T
        map = @result
        return unless map
        json = map[{{ T.name.stringify }}]?
        json.try { |j| T.from_json(j) }
      end

      # Require host-only result metadata.
      def require_result(type : T.class) : T forall T
        val = result(T)
        val || raise MissingToolContext.new({{ T.name.stringify }})
      end

      # -- Dispatch semantics --

      # Build a fresh execution context with the same inbound values and no
      # result metadata.
      def for_dispatch : ToolContext
        inbound_only
      end

      # A context carrying only the inbound values, with no result metadata.
      # Used to hand the caller's inbound context to a sub-agent invoked as a
      # tool (upstream `ToolContext::inbound_only`).
      def inbound_only : ToolContext
        cloned = ToolContext.allocate
        if inbound = @inbound
          cloned.initialize_with_inbound(inbound.dup)
        else
          cloned.initialize_with_inbound(nil)
        end
        cloned
      end

      # Publish metadata produced by one dispatch while preserving the caller's
      # inbound values.
      def accept_dispatch_result(dispatched : ToolContext)
        @result = dispatched.@result
      end

      # Clear metadata from the previous dispatch before starting another one.
      def clear_dispatch_result
        @result = nil
      end
    end

    # Legacy alias for backward compatibility.
    MissingExtension = MissingToolContext

    # Legacy aliases — deprecated, use ToolContext instead.
    class ToolCallExtensions < ToolContext
    end

    class ToolResultExtensions
      @inner : Hash(String, String)?

      def initialize
      end

      def insert(val : T) : T? forall T
        key = {{ T.name.stringify }}
        map = @inner ||= {} of String => String
        prev_json = map[key]?
        map[key] = val.to_json
        prev_json.try { |j| T.from_json(j) }
      end

      def get(type : T.class) : T? forall T
        map = @inner
        return unless map
        json = map[{{ T.name.stringify }}]?
        json.try { |j| T.from_json(j) }
      end

      def require(type : T.class) : T forall T
        val = get(T)
        val || raise MissingToolContext.new({{ T.name.stringify }})
      end

      def get_mut(type : T.class) : T? forall T
        get(T)
      end

      def remove(type : T.class) : T? forall T
        map = @inner
        return unless map
        json = map.delete({{ T.name.stringify }})
        json.try { |j| T.from_json(j) }
      end

      def contains?(type : T.class) : Bool forall T
        !!(@inner.try(&.has_key?({{ T.name.stringify }})))
      end

      def size : Int32
        @inner.try(&.size) || 0
      end

      def empty? : Bool
        size == 0
      end
    end
  end
end
