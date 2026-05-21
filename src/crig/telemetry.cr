# Compile-time telemetry gate. Build with `-Dtelemetry` to enable OpenTelemetry spans.
# Without the flag, all telemetry methods compile to zero-cost no-ops (no OTel dependency).
{% if flag?(:telemetry) %}
  require "opentelemetry-api"
{% end %}

module Crig
  module Telemetry
    GEN_AI_OPERATION_NAME       = "gen_ai.operation.name"
    GEN_AI_PROVIDER_NAME        = "gen_ai.provider.name"
    GEN_AI_REQUEST_MODEL        = "gen_ai.request.model"
    GEN_AI_SYSTEM_INSTRUCTIONS  = "gen_ai.system_instructions"
    GEN_AI_RESPONSE_ID          = "gen_ai.response.id"
    GEN_AI_RESPONSE_MODEL       = "gen_ai.response.model"
    GEN_AI_INPUT_MESSAGES       = "gen_ai.input.messages"
    GEN_AI_OUTPUT_MESSAGES      = "gen_ai.output.messages"
    GEN_AI_USAGE_INPUT_TOKENS   = "gen_ai.usage.input_tokens"
    GEN_AI_USAGE_OUTPUT_TOKENS  = "gen_ai.usage.output_tokens"
    GEN_AI_USAGE_CACHED_INPUT   = "gen_ai.usage.cache_read.input_tokens"
    GEN_AI_USAGE_CACHE_CREATION = "gen_ai.usage.cache_creation.input_tokens"
    GEN_AI_USAGE_REASONING      = "gen_ai.usage.reasoning_tokens"

    module ProviderRequestExt(InputMessage)
      abstract def input_messages : Array(InputMessage)
      abstract def system_prompt : String?
      abstract def model_name : String
      abstract def prompt : String?

      def get_input_messages : Array(InputMessage)
        input_messages
      end

      def get_system_prompt : String?
        system_prompt
      end

      def get_model_name : String
        model_name
      end

      def get_prompt : String?
        prompt
      end
    end

    module ProviderResponseExt(OutputMessage, UsageType)
      abstract def response_id : String?
      abstract def response_model_name : String?
      abstract def output_messages : Array(OutputMessage)
      abstract def text_response : String?
      abstract def usage : UsageType?

      def get_response_id : String?
        response_id
      end

      def get_response_model_name : String?
        response_model_name
      end

      def get_output_messages : Array(OutputMessage)
        output_messages
      end

      def get_text_response : String?
        text_response
      end

      def get_usage : UsageType?
        usage
      end
    end

    module SpanCombinator
      abstract def record_token_usage(usage : Crig::Completion::GetTokenUsage) : Nil
      abstract def record_response_metadata(response) : Nil
      abstract def record_model_input(messages) : Nil
      abstract def record_model_output(messages) : Nil
    end

    # When `-Dtelemetry` is active, wraps an OpenTelemetry::API::Span and records GenAI
    # semantic convention attributes. Without the flag, every method is a zero-cost
    # no-op that the Crystal compiler will inline and elide.
    {% if flag?(:telemetry) %}
      class Span
        include SpanCombinator

        @otel_span : OpenTelemetry::API::Span?

        def initialize(@otel_span : OpenTelemetry::API::Span? = nil)
        end

        def self.current : Span
          new
        end

        def record_token_usage(usage : Crig::Completion::GetTokenUsage) : Nil
          return unless recording?

          if token_usage = usage.token_usage
            set_attribute(GEN_AI_USAGE_INPUT_TOKENS, token_usage.input_tokens)
            set_attribute(GEN_AI_USAGE_OUTPUT_TOKENS, token_usage.output_tokens)
            set_attribute(GEN_AI_USAGE_CACHED_INPUT, token_usage.cached_input_tokens)
            set_attribute(GEN_AI_USAGE_CACHE_CREATION, token_usage.cache_creation_input_tokens)
            set_attribute(GEN_AI_USAGE_REASONING, token_usage.reasoning_tokens)
          end
        end

        def record_response_metadata(response) : Nil
          return unless recording?

          if rid = response.try(&.get_response_id)
            set_attribute(GEN_AI_RESPONSE_ID, rid)
          end
          if rmodel = response.try(&.get_response_model_name)
            set_attribute(GEN_AI_RESPONSE_MODEL, rmodel)
          end
        end

        def record_model_input(messages) : Nil
          return unless recording?
          set_attribute(GEN_AI_INPUT_MESSAGES, messages.to_json)
        end

        def record_model_output(messages) : Nil
          return unless recording?
          set_attribute(GEN_AI_OUTPUT_MESSAGES, messages.to_json)
        end

        def set_attribute(key : String, value : String) : Nil
          @otel_span.try(&.set_attribute(key, value))
        end

        def set_attribute(key : String, value : Int32 | Int64) : Nil
          @otel_span.try(&.set_attribute(key, value))
        end

        def set_attribute(key : String, value : Float64) : Nil
          @otel_span.try(&.set_attribute(key, value))
        end

        def set_attribute(key : String, value : Bool) : Nil
          @otel_span.try(&.set_attribute(key, value))
        end

        def recording? : Bool
          !!@otel_span.try(&.recording?)
        end

        # ameba:disable Naming/PredicateName
        def is_disabled : Bool
          !recording?
        end

        def in_scope(&)
          yield
        end
      end
    {% else %}
      struct Span
        include SpanCombinator

        def self.current : Span
          new
        end

        def set_attribute(key : String, value) : Nil
        end

        def record_token_usage(usage : Crig::Completion::GetTokenUsage) : Nil
        end

        def record_response_metadata(response) : Nil
        end

        def record_model_input(messages) : Nil
        end

        def record_model_output(messages) : Nil
        end

        # ameba:disable Naming/PredicateName
        def is_disabled : Bool
          true
        end

        def in_scope(&)
          yield
        end
      end
    {% end %}
  end

  alias ProviderRequestExt = Telemetry::ProviderRequestExt
  alias ProviderResponseExt = Telemetry::ProviderResponseExt
  alias SpanCombinator = Telemetry::SpanCombinator
  alias Span = Telemetry::Span
end
