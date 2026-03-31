module Crig
  module JSONUtils
    def self.empty_or_none(value : String?) : Bool
      value.nil? || value.empty?
    end

    def self.merge(a : JSON::Any, b : JSON::Any) : JSON::Any
      left = a.as_h?
      right = b.as_h?
      return a unless left && right

      merged = left.dup
      right.each do |key, value|
        merged[key] = value
      end
      JSON.parse(merged.to_json)
    end

    def self.merge_inplace(a : JSON::Any, b : JSON::Any) : Nil
      left = a.as_h?
      right = b.as_h?
      return unless left && right

      right.each do |key, value|
        left[key] = value
      end
    end

    def self.value_to_json_string(value : JSON::Any) : String
      value.raw.is_a?(String) ? value.as_s : value.to_json
    end

    module StringifiedJSON
      def self.to_json(value : JSON::Any, json : JSON::Builder) : Nil
        json.string(value.to_json)
      end

      def self.from_json(pull : JSON::PullParser) : JSON::Any
        string = pull.read_string
        return JSON.parse(%({})) if string.strip.empty?

        JSON.parse(string)
      end
    end

    module StringOrVecConverter(T)
      def self.from_json(pull : JSON::PullParser) : Array(T)
        case pull.kind
        when .begin_array?
          Array(T).new(pull)
        when .string?
          val = pull.read_string
          [convert(val)].as(Array(T))
        when .int?
          val = pull.read_int
          [convert(val)].as(Array(T))
        when .float?
          val = pull.read_float
          [convert(val)].as(Array(T))
        else
          Array(T).new(pull)
        end
      end

      private def self.convert(val : String) : T
        {% if T == String %}
          val
        {% else %}
          T.new(val)
        {% end %}
      end

      private def self.convert(val : Int64) : T
        {% if T == String %}
          val.to_s
        {% else %}
          T.new(val)
        {% end %}
      end

      private def self.convert(val : Float64) : T
        {% if T == String %}
          val.to_s
        {% else %}
          T.new(val)
        {% end %}
      end

      def self.to_json(value : Array(T), json : JSON::Builder) : Nil
        value.to_json(json)
      end
    end

    module NullOrVecConverter(T)
      def self.from_json(pull : JSON::PullParser) : Array(T)
        if pull.kind.null?
          pull.read_null
          [] of T
        else
          Array(T).new(pull)
        end
      end

      def self.to_json(value : Array(T), json : JSON::Builder) : Nil
        value.to_json(json)
      end
    end
  end
end
