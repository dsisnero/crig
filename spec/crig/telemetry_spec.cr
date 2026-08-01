require "../spec_helper"

# Builds a span metadata with the given declared field names.
def telemetry_parent_metadata(field_names : Array(String)) : Tracing::Core::Metadata
  fields = Tracing::Field::FieldSet.new(field_names.map { |n| Tracing::Field::Field.new(n) })
  Tracing::Core::Metadata.new("chat", "test", Tracing::Level::INFO, fields: fields)
end

# Captures (field, value) pairs recorded on spans.
class TelemetryCapturingSubscriber < Tracing::MockSubscriber
  getter fields = [] of {String, String}

  def record(id : Tracing::Core::Span::Id, values : Tracing::Core::Span::Record) : Nil
    visitor = FieldVisitor.new
    values.values.visit(visitor)
    @fields.concat(visitor.pairs)
  end

  private class FieldVisitor
    include Tracing::Field::Visit

    getter pairs = [] of {String, String}

    def record_debug(field : Tracing::Field::Field, value) : Nil
      @pairs << {field.name, value.to_s}
    end

    def record_i64(field : Tracing::Field::Field, value : Int64) : Nil
      @pairs << {field.name, value.to_s}
    end

    def record_u64(field : Tracing::Field::Field, value : UInt64) : Nil
      @pairs << {field.name, value.to_s}
    end

    def record_f64(field : Tracing::Field::Field, value : Float64) : Nil
      @pairs << {field.name, value.to_s}
    end

    def record_bool(field : Tracing::Field::Field, value : Bool) : Nil
      @pairs << {field.name, value.to_s}
    end

    def record_str(field : Tracing::Field::Field, value : String) : Nil
      @pairs << {field.name, value}
    end

    def record_error(field : Tracing::Field::Field, value : Exception) : Nil
      @pairs << {field.name, value.message.to_s}
    end
  end
end

module Crig
  describe "content telemetry" do
    it "records model input messages on the chat span when enabled" do
      sub = TelemetryCapturingSubscriber.new
      Tracing::Core::Dispatch.with_default(Tracing::Core::Dispatch.new(sub)) do
        span = Span.chat_span("openai", "gpt-4o", "be concise", %([{"role":"user","content":"hi"}]))
        span.end_span
      end

      pair = sub.fields.find { |(k, _)| k == "gen_ai.input.messages" }
      pair.should_not be_nil
      pair.not_nil![1].should contain("user")
    end

    it "records model output when content telemetry is enabled" do
      sub = TelemetryCapturingSubscriber.new
      Tracing::Core::Dispatch.with_default(Tracing::Core::Dispatch.new(sub)) do
        span = Span.chat_span("openai", "gpt-4o", nil, nil)
        span.record_model_output(%([{"role":"assistant","content":"hi"}]))
        span.end_span
      end

      pair = sub.fields.find { |(k, _)| k == "gen_ai.output.messages" }
      pair.should_not be_nil
      pair.not_nil![1].should contain("assistant")
    end

    it "records tool call arguments when content telemetry is enabled" do
      sub = TelemetryCapturingSubscriber.new
      Tracing::Core::Dispatch.with_default(Tracing::Core::Dispatch.new(sub)) do
        span = Span.chat_span("openai", "gpt-4o", nil, nil)
        span.record_tool_call_args("weather", "call_1", %({"city":"Denver"}))
        span.end_span
      end

      pair = sub.fields.find { |(k, _)| k == "gen_ai.tool.call.arguments" }
      pair.should_not be_nil
      pair.not_nil![1].should contain("Denver")
    end
  end
end

module Crig
  describe "runner content telemetry" do
    it "records model input and output when content telemetry is enabled" do
      sub = TelemetryCapturingSubscriber.new
      Tracing::Core::Dispatch.with_default(Tracing::Core::Dispatch.new(sub)) do
        model = RunnerMockModel.new
        model.response_text = "Hi there!"
        runner = AgentRunner(typeof(model)).new(model)
          .record_content_telemetry(true)

        runner.run(Completion::Message.user("hello"))
      end

      input = sub.fields.find { |(k, _)| k == "gen_ai.input.messages" }
      output = sub.fields.find { |(k, _)| k == "gen_ai.output.messages" }
      input.should_not be_nil
      output.should_not be_nil
      output.not_nil![1].should contain("Hi there!")
    end

    it "does not record model content when content telemetry is disabled" do
      sub = TelemetryCapturingSubscriber.new
      Tracing::Core::Dispatch.with_default(Tracing::Core::Dispatch.new(sub)) do
        model = RunnerMockModel.new
        model.response_text = "Hi there!"
        runner = AgentRunner(typeof(model)).new(model)

        runner.run(Completion::Message.user("hello"))
      end

      sub.fields.find { |(k, _)| k == "gen_ai.input.messages" }.should be_nil
      sub.fields.find { |(k, _)| k == "gen_ai.output.messages" }.should be_nil
    end

    it "does not record system instructions when content telemetry is disabled" do
      sub = TelemetryCapturingSubscriber.new
      Tracing::Core::Dispatch.with_default(Tracing::Core::Dispatch.new(sub)) do
        span = Span.chat_span("openai", "gpt-4o", "be concise", nil, false)
        span.end_span
      end

      sub.fields.find { |(k, _)| k == "gen_ai.system_instructions" }.should be_nil
    end

    it "records system instructions when content telemetry is enabled" do
      sub = TelemetryCapturingSubscriber.new
      Tracing::Core::Dispatch.with_default(Tracing::Core::Dispatch.new(sub)) do
        span = Span.chat_span("openai", "gpt-4o", "be concise", nil, true)
        span.end_span
      end

      pair = sub.fields.find { |(k, _)| k == "gen_ai.system_instructions" }
      pair.should_not be_nil
      pair.not_nil![1].should eq("be concise")
    end
  end

  describe "completion-parent classification" do
    it "classifies a span without the marker as NotAParent" do
      meta = telemetry_parent_metadata(["gen_ai.operation.name"])
      Telemetry.classify_completion_parent(meta).should eq(Telemetry::CompletionParentVerdict::NotAParent)
    end

    it "classifies a span with the marker and all required fields as Adopt" do
      meta = telemetry_parent_metadata(["rig.completion_parent"] + Telemetry::COMPLETION_PARENT_REQUIRED_FIELDS)
      Telemetry.classify_completion_parent(meta).should eq(Telemetry::CompletionParentVerdict::Adopt)
    end

    it "classifies a marker span missing required fields as RejectMissingFields" do
      meta = telemetry_parent_metadata(["rig.completion_parent", "gen_ai.operation.name"])
      Telemetry.classify_completion_parent(meta).should eq(Telemetry::CompletionParentVerdict::RejectMissingFields)
    end

    it "reports the missing required field names" do
      meta = telemetry_parent_metadata(["rig.completion_parent", "gen_ai.operation.name"])
      missing = Telemetry.missing_required_fields(meta)

      missing.includes?("gen_ai.response.id").should be_true
      missing.includes?("gen_ai.usage.input_tokens").should be_true
      missing.includes?("gen_ai.input.messages").should be_true
    end

    it "treats a prefix of the marker name as not-a-marker" do
      meta = telemetry_parent_metadata(["rig.completion_parent.id"])
      Telemetry.classify_completion_parent(meta).should eq(Telemetry::CompletionParentVerdict::NotAParent)
    end
  end
end
