require "./spec_helper"
require "tracing"

class FieldCaptureLayer < Tracing::Layer
  getter captured : Array(Tuple(String, Int64))

  def initialize
    @captured = [] of Tuple(String, Int64)
  end

  def on_record(id : Tracing::Core::Span::Id, values : Tracing::Core::Span::Record, ctx : Tracing::LayerContext) : Nil
    visitor = FieldCaptureVisitor.new(self)
    values.values.visit(visitor)
  end

  struct FieldCaptureVisitor
    include Tracing::Field::Visit

    def initialize(@layer : FieldCaptureLayer)
    end

    def record_debug(field : Tracing::Field::Field, value) : Nil
    end

    def record_i64(field : Tracing::Field::Field, value : Int64) : Nil
      @layer.captured << {field.name, value}
    end

    def record_u64(field : Tracing::Field::Field, value : UInt64) : Nil
      @layer.captured << {field.name, value.to_i64}
    end

    def record_f64(field : Tracing::Field::Field, value : Float64) : Nil
    end

    def record_bool(field : Tracing::Field::Field, value : Bool) : Nil
    end

    def record_str(field : Tracing::Field::Field, value : String) : Nil
    end

    def record_error(field : Tracing::Field::Field, value : Exception) : Nil
    end
  end
end

describe "record_token_usage tool_use_prompt_tokens via Tracing::Layer" do
  it "records tool_use_prompt_tokens in span attributes (mirrors upstream FieldCaptureLayer)" do
    usage = Crig::Completion::Usage.new(
      input_tokens: 1,
      output_tokens: 2,
      total_tokens: 15,
      cached_input_tokens: 3,
      cache_creation_input_tokens: 4,
      tool_use_prompt_tokens: 12,
      reasoning_tokens: 5,
    )

    layer = FieldCaptureLayer.new
    registry = Tracing::Registry.new
    subscriber = registry.with(layer)

    Tracing::Subscriber.with_default(subscriber) do
      span = Tracing.span(Tracing::Level::INFO, "usage_recording")
      span.record(
        tool_use_prompt_tokens: usage.tool_use_prompt_tokens,
        reasoning_tokens:        usage.reasoning_tokens,
      )
    end

    layer.captured.includes?({"tool_use_prompt_tokens", 12_i64}).should be_true
    layer.captured.includes?({"reasoning_tokens", 5_i64}).should be_true
  end
end
