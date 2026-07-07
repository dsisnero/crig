module Crig
  module Tool
    class MissingExtension < Exception
      getter type_name : String

      def initialize(@type_name : String)
        super("required tool extension of type `#{@type_name}` was not found")
      end
    end

    class ToolCallExtensions
      EMPTY = new

      @inner : Hash(String, String)?

      def self.new
        inst = allocate
        inst.initialize
        inst
      end

      def initialize
      end

      def insert(val : T) : T? forall T
        key = {{T.name.stringify}}
        map = @inner ||= {} of String => String
        prev_json = map[key]?
        map[key] = val.to_json
        prev_json.try { |j| T.from_json(j) }
      end

      def get(type : T.class) : T? forall T
        map = @inner
        return nil unless map
        json = map[{{T.name.stringify}}]?
        json.try { |j| T.from_json(j) }
      rescue JSON::SerializableError
        nil
      end

      def require(type : T.class) : T forall T
        get(T).not_nil!
      rescue NilAssertionError
        raise MissingExtension.new({{T.name.stringify}})
      end

      def get_mut(type : T.class) : T? forall T
        get(T)
      end

      def remove(type : T.class) : T? forall T
        map = @inner
        return nil unless map
        key = {{T.name.stringify}}
        json = map.delete(key)
        map.delete(@inner) if map.empty? && @inner == map
        json.try { |j| T.from_json(j) }
      rescue JSON::SerializableError
        nil
      end

      def contains?(type : T.class) : Bool forall T
        !!(@inner.try(&.has_key?({{T.name.stringify}})))
      end

      def size : Int32
        @inner.try(&.size) || 0
      end

      def empty? : Bool
        size == 0
      end

      # Alias for insert
      def []=(val : T) : T? forall T
        insert(val)
      end

      # Alias for get
      def [](type : T.class) : T? forall T
        get(T)
      end
    end

    class ToolResultExtensions
      @inner : Hash(String, String)?

      def self.new
        inst = allocate
        inst.initialize
        inst
      end

      def initialize
      end

      def insert(val : T) : T? forall T
        key = {{T.name.stringify}}
        map = @inner ||= {} of String => String
        prev_json = map[key]?
        map[key] = val.to_json
        prev_json.try { |j| T.from_json(j) }
      end

      def get(type : T.class) : T? forall T
        map = @inner
        return nil unless map
        json = map[{{T.name.stringify}}]?
        json.try { |j| T.from_json(j) }
      rescue JSON::SerializableError
        nil
      end

      def require(type : T.class) : T forall T
        get(T).not_nil!
      rescue NilAssertionError
        raise MissingExtension.new({{T.name.stringify}})
      end

      def get_mut(type : T.class) : T? forall T
        get(T)
      end

      def remove(type : T.class) : T? forall T
        map = @inner
        return nil unless map
        json = map.delete({{T.name.stringify}})
        json.try { |j| T.from_json(j) }
      rescue JSON::SerializableError
        nil
      end

      def contains?(type : T.class) : Bool forall T
        !!(@inner.try(&.has_key?({{T.name.stringify}})))
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
