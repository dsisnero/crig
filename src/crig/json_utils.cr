module Crig
  module JSONUtils
    def self.empty_or_none(value : String?) : Bool
      value.nil? || value.empty?
    end

    def self.deserialize_json_string_or_value(raw : String) : String?
      return if raw.strip.empty?

      value = JSON.parse(raw)
      inner = value.raw

      case inner
      when Nil    then nil
      when String then inner
      else             JSONUtils.value_to_json_string(value)
      end
    rescue JSON::ParseException
      nil
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

    def self.parse_tool_arguments(arguments : String) : JSON::Any
      return JSON.parse(%({})) if arguments.strip.empty?

      JSON.parse(arguments)
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

      def self.deserialize_maybe_stringified(pull : JSON::PullParser) : JSON::Any
        case pull.kind
        when .string?
          Crig::JSONUtils.parse_tool_arguments(pull.read_string)
        else
          JSON::Any.new(pull)
        end
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

    module NullOrDefault(T)
      def self.from_json(pull : JSON::PullParser) : T
        if pull.kind.null?
          pull.read_null
          T.from_json(%({}))
        else
          T.new(pull)
        end
      end

      def self.to_json(value : T, json : JSON::Builder) : Nil
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

    def self.merge_text_additional_params(existing : JSON::Any, incoming : JSON::Any) : Nil
      existing_h = existing.as_h?
      incoming_h = incoming.as_h?
      return unless existing_h && incoming_h

      incoming_h.each do |key, incoming_value|
        if curr = existing_h[key]?
          if curr.as_a? && incoming_value.as_a?
            curr.as_a.concat(incoming_value.as_a)
          elsif curr.as_h? && incoming_value.as_h?
            merge_text_additional_params(curr, incoming_value)
          else
            existing_h[key] = incoming_value
          end
        else
          existing_h[key] = incoming_value
        end
      end
    end
  end
end
