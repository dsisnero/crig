require "./spec_helper"

describe "Usage.tool_use_prompt_tokens" do
  it "deserializes tool_use_prompt_tokens from JSON with default 0" do
    usage = Crig::Completion::Usage.from_json(%({"input_tokens":100,"output_tokens":50,"total_tokens":150,"tool_use_prompt_tokens":25}))
    usage.tool_use_prompt_tokens.should eq(25)
    usage.input_tokens.should eq(100)
    usage.output_tokens.should eq(50)
  end

  it "defaults tool_use_prompt_tokens to 0 when absent from JSON" do
    usage = Crig::Completion::Usage.from_json(%({"input_tokens":10,"output_tokens":20,"total_tokens":30}))
    usage.tool_use_prompt_tokens.should eq(0)
  end

  it "includes tool_use_prompt_tokens in addition" do
    usage1 = Crig::Completion::Usage.new(input_tokens: 10, output_tokens: 5, total_tokens: 15, tool_use_prompt_tokens: 3)
    usage2 = Crig::Completion::Usage.new(input_tokens: 20, output_tokens: 10, total_tokens: 30, tool_use_prompt_tokens: 7)

    combined = usage1 + usage2
    combined.input_tokens.should eq(30)
    combined.output_tokens.should eq(15)
    combined.total_tokens.should eq(45)
    combined.tool_use_prompt_tokens.should eq(10)
  end

  it "creates default Usage with all fields zero" do
    usage = Crig::Completion::Usage.new
    usage.tool_use_prompt_tokens.should eq(0)
    usage.input_tokens.should eq(0)
  end
end
