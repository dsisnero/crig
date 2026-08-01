require "tracing"

# Reopen Tracing::Span for gen_ai semantic convention field recording.
class Tracing::Span
  def record_field(key : String, value : String) : Nil
    return if disabled?
    vs = Tracing::Field::ValueSet.new
    vs.record(Tracing::Field::Field.new(key), value)
    inner_subscriber_record(vs)
  end

  def record_field(key : String, value : Int32 | Int64) : Nil
    return if disabled?
    vs = Tracing::Field::ValueSet.new
    vs.record(Tracing::Field::Field.new(key), value)
    inner_subscriber_record(vs)
  end

  def record_field(key : String, value : Float64) : Nil
    return if disabled?
    vs = Tracing::Field::ValueSet.new
    vs.record(Tracing::Field::Field.new(key), value)
    inner_subscriber_record(vs)
  end

  def record_field(key : String, value : Bool) : Nil
    return if disabled?
    vs = Tracing::Field::ValueSet.new
    vs.record(Tracing::Field::Field.new(key), value)
    inner_subscriber_record(vs)
  end

  private def inner_subscriber_record(vs : Tracing::Field::ValueSet) : Nil
    if inner = @inner
      inner.subscriber.record(inner.id, Tracing::Core::Span::Record.new(vs))
    end
  end
end

module Crig
  module Telemetry
    GEN_AI_OPERATION_NAME        = "gen_ai.operation.name"
    GEN_AI_PROVIDER_NAME         = "gen_ai.provider.name"
    GEN_AI_REQUEST_MODEL         = "gen_ai.request.model"
    GEN_AI_SYSTEM_INSTRUCTIONS   = "gen_ai.system_instructions"
    GEN_AI_RESPONSE_ID           = "gen_ai.response.id"
    GEN_AI_RESPONSE_MODEL        = "gen_ai.response.model"
    GEN_AI_INPUT_MESSAGES        = "gen_ai.input.messages"
    GEN_AI_OUTPUT_MESSAGES       = "gen_ai.output.messages"
    GEN_AI_USAGE_INPUT_TOKENS    = "gen_ai.usage.input_tokens"
    GEN_AI_USAGE_OUTPUT_TOKENS   = "gen_ai.usage.output_tokens"
    GEN_AI_USAGE_CACHED_INPUT    = "gen_ai.usage.cache_read.input_tokens"
    GEN_AI_USAGE_CACHE_CREATION  = "gen_ai.usage.cache_creation.input_tokens"
    GEN_AI_USAGE_TOOL_USE_PROMPT = "gen_ai.usage.tool_use_prompt_tokens"
    GEN_AI_USAGE_REASONING       = "gen_ai.usage.reasoning_tokens"
    GEN_AI_AGENT_NAME            = "gen_ai.agent.name"
    GEN_AI_PROMPT                = "gen_ai.prompt"
    GEN_AI_COMPLETION            = "gen_ai.completion"

    # Marker a completion-parent span must declare to be adopted by a
    # completion-span builder (upstream COMPLETION_PARENT_MARKER_FIELD).
    COMPLETION_PARENT_MARKER_FIELD = "rig.completion_parent"

    # Fields a completion-parent span must statically declare, alongside the
    # marker, to be adopted (upstream COMPLETION_PARENT_REQUIRED_FIELDS).
    COMPLETION_PARENT_REQUIRED_FIELDS = [
      "gen_ai.operation.name",
      "gen_ai.provider.name",
      "gen_ai.request.model",
      "gen_ai.system_instructions",
      "gen_ai.response.id",
      "gen_ai.response.model",
      "gen_ai.usage.input_tokens",
      "gen_ai.usage.output_tokens",
      "gen_ai.usage.cache_read.input_tokens",
      "gen_ai.usage.cache_creation.input_tokens",
      "gen_ai.usage.tool_use_prompt_tokens",
      "gen_ai.usage.reasoning_tokens",
      "gen_ai.input.messages",
      "gen_ai.output.messages",
    ]

    enum CompletionParentVerdict
      Adopt
      RejectMissingFields
      NotAParent
    end

    # Whether `metadata` declares the given field (exact name match).
    private def self.declares_field?(metadata : Tracing::Core::Metadata, name : String) : Bool
      metadata.fields.fields.any? { |field| field.name == name }
    end

    # Fields in COMPLETION_PARENT_REQUIRED_FIELDS that `metadata` does not
    # statically declare. Only called on the warning path.
    def self.missing_required_fields(metadata : Tracing::Core::Metadata) : Array(String)
      COMPLETION_PARENT_REQUIRED_FIELDS.reject { |name| declares_field?(metadata, name) }
    end

    # Classify span `metadata` as a completion parent (upstream
    # `classify_completion_parent`). Pure: no logging, no global state.
    def self.classify_completion_parent(metadata : Tracing::Core::Metadata) : CompletionParentVerdict
      # Exact match, never a prefix: a runtime field that merely starts with the
      # marker name (rig.completion_parent.id, say) is not the marker.
      return CompletionParentVerdict::NotAParent unless declares_field?(metadata, COMPLETION_PARENT_MARKER_FIELD)

      if COMPLETION_PARENT_REQUIRED_FIELDS.all? { |name| declares_field?(metadata, name) }
        CompletionParentVerdict::Adopt
      else
        CompletionParentVerdict::RejectMissingFields
      end
    end

    module ProviderRequestExt(InputMessage)
      abstract def input_messages : Array(InputMessage)
      abstract def system_prompt : String?
      abstract def model_name : String
      abstract def prompt : String?

      def get_input_messages : Array(InputMessage) # ameba:disable Naming/AccessorMethodName
        input_messages
      end

      def get_system_prompt : String? # ameba:disable Naming/AccessorMethodName
        system_prompt
      end

      def get_model_name : String # ameba:disable Naming/AccessorMethodName
        model_name
      end

      def get_prompt : String? # ameba:disable Naming/AccessorMethodName
        prompt
      end
    end

    module ProviderResponseExt(OutputMessage, UsageType)
      abstract def response_id : String?
      abstract def response_model_name : String?
      abstract def output_messages : Array(OutputMessage)
      abstract def text_response : String?
      abstract def usage : UsageType?

      def get_response_id : String? # ameba:disable Naming/AccessorMethodName
        response_id
      end

      def get_response_model_name : String? # ameba:disable Naming/AccessorMethodName
        response_model_name
      end

      def get_output_messages : Array(OutputMessage) # ameba:disable Naming/AccessorMethodName
        output_messages
      end

      def get_text_response : String? # ameba:disable Naming/AccessorMethodName
        text_response
      end

      def get_usage : UsageType? # ameba:disable Naming/AccessorMethodName
        usage
      end
    end

    # Implemented on Tracing::Span, mirroring Rust `impl SpanCombinator for tracing::Span`.
    module SpanCombinator
      def record_token_usage(usage : Crig::Completion::GetTokenUsage) : Nil
        return if disabled?
        return unless tu = usage.token_usage

        record_field(GEN_AI_USAGE_INPUT_TOKENS, tu.input_tokens)
        record_field(GEN_AI_USAGE_OUTPUT_TOKENS, tu.output_tokens)
        record_field(GEN_AI_USAGE_CACHED_INPUT, tu.cached_input_tokens)
        record_field(GEN_AI_USAGE_CACHE_CREATION, tu.cache_creation_input_tokens)
        record_field(GEN_AI_USAGE_TOOL_USE_PROMPT, tu.tool_use_prompt_tokens)
        record_field(GEN_AI_USAGE_REASONING, tu.reasoning_tokens)
      end

      def record_response_metadata(response) : Nil
        return if disabled?

        if rid = response.try(&.get_response_id)
          record_field(GEN_AI_RESPONSE_ID, rid)
        end
        if rmodel = response.try(&.get_response_model_name)
          record_field(GEN_AI_RESPONSE_MODEL, rmodel)
        end
      end
    end

    class Span
      include SpanCombinator

      @inner : Tracing::Span

      def initialize(@inner : Tracing::Span)
      end

      # Create a provider-level chat span.
      def self.current : Span
        meta = Tracing::Metadata.new("current", "crig", Tracing::Level::INFO)
        new(Tracing::Span.new(meta))
      end

      def self.for_tracer(name : String, operation : String) : Span
        meta = Tracing::Metadata.new(operation, name, Tracing::Level::INFO)
        new(Tracing::Span.new(meta))
      end

      def self.chat_span(provider_name : String, model : String, preamble : String?, request_messages_json : String?, record_content : Bool = false) : Span
        meta = Tracing::Metadata.new("chat", "crig", Tracing::Level::INFO)
        inner = Tracing::Span.new(meta)
        span = new(inner)
        span.record_field(GEN_AI_OPERATION_NAME, "chat")
        span.record_field(GEN_AI_PROVIDER_NAME, provider_name)
        span.record_field(GEN_AI_REQUEST_MODEL, model)
        if record_content && preamble
          span.record_field(GEN_AI_SYSTEM_INSTRUCTIONS, preamble)
        end
        if request_messages_json
          span.record_field(GEN_AI_INPUT_MESSAGES, request_messages_json)
        end
        span
      end

      # Record serialized model input on gen_ai.input.messages when content
      # telemetry is explicitly enabled (upstream `record_model_input`).
      def record_model_input(json : String?) : Nil
        return if disabled? || json.nil?
        record_field(GEN_AI_INPUT_MESSAGES, json)
      end

      # Record serialized model output on gen_ai.output.messages when content
      # telemetry is explicitly enabled (upstream `record_model_output`).
      def record_model_output(json : String?) : Nil
        return if disabled? || json.nil?
        record_field(GEN_AI_OUTPUT_MESSAGES, json)
      end

      # Record tool-call arguments when content telemetry is enabled
      # (upstream records gen_ai.tool.call.arguments when opted in).
      def record_tool_call_args(name : String, call_id : String?, args : String?) : Nil
        return if disabled?
        record_field("gen_ai.tool.name", name)
        if call_id
          record_field("gen_ai.tool.call.id", call_id)
        end
        if args
          record_field("gen_ai.tool.call.arguments", args)
        end
      end

      def set_attribute(key : String, value : String) : Nil
        record_field(key, value)
      end

      def set_attribute(key : String, value : Int32 | Int64) : Nil
        record_field(key, value)
      end

      def set_attribute(key : String, value : Float64) : Nil
        record_field(key, value)
      end

      def set_attribute(key : String, value : Bool) : Nil
        record_field(key, value)
      end

      def recording? : Bool
        !@inner.disabled?
      end

      def disabled? : Bool
        @inner.disabled?
      end

      def end_span : Nil
        @inner.exit_span
      end

      def in_scope(&)
        @inner.in_scope { yield }
      end

      # Delegate record_field to inner Tracing::Span
      def record_field(key : String, value : String) : Nil
        @inner.record_field(key, value)
      end

      def record_field(key : String, value : Int32 | Int64) : Nil
        @inner.record_field(key, value)
      end

      def record_field(key : String, value : Float64) : Nil
        @inner.record_field(key, value)
      end

      def record_field(key : String, value : Bool) : Nil
        @inner.record_field(key, value)
      end
    end
  end

  alias ProviderRequestExt = Telemetry::ProviderRequestExt
  alias ProviderResponseExt = Telemetry::ProviderResponseExt
  alias SpanCombinator = Telemetry::SpanCombinator
  alias Span = Telemetry::Span
end
