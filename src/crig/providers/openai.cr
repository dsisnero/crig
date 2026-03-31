module Crig
  module Providers
    module OpenAI
      OPENAI_API_BASE_URL = "https://api.openai.com/v1"
      VARIANT_KEYS        = {"anyOf", "oneOf", "allOf"}

      def self.sanitize_schema(schema : JSON::Any) : JSON::Any
        sanitize_schema_value(schema)
      end

      def self.merge_json_hashes(
        left : Hash(String, JSON::Any),
        right : Hash(String, JSON::Any),
      ) : Hash(String, JSON::Any)
        merged = left.dup
        right.each do |key, value|
          merged[key] = if existing = merged[key]?
                          merge_json_values(existing, value)
                        else
                          value
                        end
        end
        merged
      end

      def self.merge_json_values(left : JSON::Any, right : JSON::Any) : JSON::Any
        left_hash = left.as_h?
        right_hash = right.as_h?
        return right unless left_hash && right_hash
        JSON.parse(merge_json_hashes(left_hash, right_hash).to_json)
      end

      private def self.sanitize_schema_value(schema : JSON::Any) : JSON::Any
        return sanitize_object(schema.as_h) if schema.as_h?
        return sanitize_array(schema.as_a) if schema.as_a?
        schema
      end

      private def self.sanitize_object(object : Hash(String, JSON::Any)) : JSON::Any
        return sanitize_ref_object(object) if object.has_key?("$ref")

        sanitized = object.dup
        ensure_object_restrictions(sanitized)
        sanitize_defs!(sanitized)
        sanitize_properties!(sanitized)
        sanitize_items!(sanitized)
        merge_one_of_into_any_of!(sanitized)
        sanitize_variants!(sanitized)
        JSON.parse(sanitized.to_json)
      end

      private def self.sanitize_ref_object(object : Hash(String, JSON::Any)) : JSON::Any
        JSON.parse({"$ref" => object["$ref"]}.to_json)
      end

      private def self.ensure_object_restrictions(schema : Hash(String, JSON::Any)) : Nil
        return unless object_schema?(schema)

        schema["additionalProperties"] = JSON::Any.new(false) unless schema.has_key?("additionalProperties")
        return unless properties = schema["properties"]?.try(&.as_h?)

        schema["required"] = JSON::Any.new(properties.keys.map { |key| JSON::Any.new(key) })
      end

      private def self.object_schema?(schema : Hash(String, JSON::Any)) : Bool
        schema["type"]?.try(&.as_s?) == "object" || schema.has_key?("properties")
      end

      private def self.sanitize_defs!(schema : Hash(String, JSON::Any)) : Nil
        return unless defs = schema["$defs"]?.try(&.as_h?)

        defs.each do |key, value|
          schema["$defs"].as_h[key] = sanitize_schema_value(value)
        end
      end

      private def self.sanitize_properties!(schema : Hash(String, JSON::Any)) : Nil
        return unless properties = schema["properties"]?.try(&.as_h?)

        properties.each do |key, value|
          schema["properties"].as_h[key] = sanitize_schema_value(value)
        end
      end

      private def self.sanitize_items!(schema : Hash(String, JSON::Any)) : Nil
        return unless items = schema["items"]?

        schema["items"] = sanitize_schema_value(items)
      end

      private def self.merge_one_of_into_any_of!(schema : Hash(String, JSON::Any)) : Nil
        return unless one_of = schema.delete("oneOf")

        if any_of = schema["anyOf"]?.try(&.as_a?)
          schema["anyOf"] = JSON.parse((any_of + one_of.as_a).to_json)
        else
          schema["anyOf"] = one_of
        end
      end

      private def self.sanitize_variants!(schema : Hash(String, JSON::Any)) : Nil
        VARIANT_KEYS.each do |key|
          next unless variants = schema[key]?.try(&.as_a?)
          schema[key] = sanitize_array(variants)
        end
      end

      private def self.sanitize_array(array : Array(JSON::Any)) : JSON::Any
        JSON.parse(array.map { |item| sanitize_schema_value(item) }.to_json)
      end
    end
  end
end

require "./openai/client"
require "./openai/audio_generation"
require "./openai/completion"
require "./openai/embedding"
require "./openai/image_generation"
require "./openai/responses_api"
require "./openai/responses_api/streaming"
require "./openai/transcription"
