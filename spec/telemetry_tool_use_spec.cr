require "./spec_helper"

struct RecordTokenUsageSpan
  include Crig::Telemetry::SpanCombinator

  getter attributes : Hash(String, Int64)

  def initialize
    @attributes = {} of String => Int64
  end

  def record_token_usage(usage : Crig::Completion::GetTokenUsage) : Nil
    if token_usage = usage.token_usage
      @attributes["gen_ai.usage.input_tokens"] = token_usage.input_tokens
      @attributes["gen_ai.usage.output_tokens"] = token_usage.output_tokens
      @attributes["gen_ai.usage.cache_read.input_tokens"] = token_usage.cached_input_tokens
      @attributes["gen_ai.usage.cache_creation.input_tokens"] = token_usage.cache_creation_input_tokens
      @attributes["gen_ai.usage.tool_use_prompt_tokens"] = token_usage.tool_use_prompt_tokens
      @attributes["gen_ai.usage.reasoning_tokens"] = token_usage.reasoning_tokens
    end
  end

  def record_response_metadata(response) : Nil
  end

  def record_model_input(messages) : Nil
  end

  def record_model_output(messages) : Nil
  end
end

describe "record_token_usage tool_use_prompt_tokens" do
  it "records tool_use_prompt_tokens in span attributes" do
    usage = Crig::Completion::Usage.new(
      input_tokens: 1,
      output_tokens: 2,
      total_tokens: 15,
      cached_input_tokens: 3,
      cache_creation_input_tokens: 4,
      tool_use_prompt_tokens: 12,
      reasoning_tokens: 5,
    )

    span = RecordTokenUsageSpan.new
    span.record_token_usage(usage)

    span.attributes["gen_ai.usage.tool_use_prompt_tokens"].should eq(12)
    span.attributes["gen_ai.usage.reasoning_tokens"].should eq(5)
    span.attributes["gen_ai.usage.input_tokens"].should eq(1)
  end

  it "records zero for tool_use_prompt_tokens when default usage" do
    usage = Crig::Completion::Usage.new(input_tokens: 10, output_tokens: 20, total_tokens: 30)
    span = RecordTokenUsageSpan.new
    span.record_token_usage(usage)
    span.attributes["gen_ai.usage.tool_use_prompt_tokens"].should eq(0)
  end
end
