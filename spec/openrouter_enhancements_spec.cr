require "./spec_helper"

describe "OpenRouter PromptTokensDetails" do
  it "deserializes usage with cache token details" do
    json = %({
      "prompt_tokens": 100,
      "completion_tokens": 50,
      "total_tokens": 150,
      "prompt_tokens_details": {
        "cached_tokens": 30,
        "cache_write_tokens": 10
      }
    })
    usage = Crig::Providers::OpenRouter::Usage.from_json(json)
    usage.prompt_tokens.should eq(100)
    usage.completion_tokens.should eq(50)
    usage.total_tokens.should eq(150)
    usage.prompt_tokens_details.should_not be_nil
    details = usage.prompt_tokens_details.not_nil!
    details.cached_tokens.should eq(30)
    details.cache_write_tokens.should eq(10)
  end

  it "maps cache tokens to Completion::Usage through token_usage" do
    json = %({
      "prompt_tokens": 10,
      "completion_tokens": 20,
      "total_tokens": 30,
      "prompt_tokens_details": {
        "cached_tokens": 5,
        "cache_write_tokens": 3
      }
    })
    usage = Crig::Providers::OpenRouter::Usage.from_json(json)
    rig_usage = usage.token_usage.not_nil!
    rig_usage.cached_input_tokens.should eq(5)
    rig_usage.cache_creation_input_tokens.should eq(3)
    rig_usage.tool_use_prompt_tokens.should eq(0)
  end

  it "defaults cache tokens to 0 when prompt_tokens_details is absent" do
    json = %({"prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30})
    usage = Crig::Providers::OpenRouter::Usage.from_json(json)
    usage.prompt_tokens_details.should be_nil
    rig_usage = usage.token_usage.not_nil!
    rig_usage.cached_input_tokens.should eq(0)
    rig_usage.cache_creation_input_tokens.should eq(0)
  end
end

describe "OpenRouter Gemini model role" do
  it "accepts role: model as alias for role: assistant" do
    value = JSON.parse(%({"role":"model","content":"Hello from Gemini"}))
    msg = Crig::Providers::OpenRouter::Message.from_json_value(value)
    msg.kind.assistant?.should be_true
  end

  it "still accepts role: assistant" do
    value = JSON.parse(%({"role":"assistant","content":"Hello"}))
    msg = Crig::Providers::OpenRouter::Message.from_json_value(value)
    msg.kind.assistant?.should be_true
  end
end
