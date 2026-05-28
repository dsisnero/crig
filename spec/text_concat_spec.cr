require "./spec_helper"

describe "Text Concatenation" do
  it "anthropic text_response concatenates text blocks without newline separator" do
    text1 = Crig::Providers::Anthropic::Content.text("hello")
    text2 = Crig::Providers::Anthropic::Content.text("world")
    response = Crig::Providers::Anthropic::CompletionResponse.new(
      [text1, text2],
      "msg_123",
      "claude-3-5-sonnet",
      "assistant",
      Crig::Providers::Anthropic::Usage.new(0_i64, 0_i64),
      "end_turn",
    )
    response.text_response.should eq("helloworld")
  end

  it "text_response returns nil when content has no text blocks" do
    tool_use = Crig::Providers::Anthropic::Content.tool_use("id1", "search", JSON.parse(%({})))
    response = Crig::Providers::Anthropic::CompletionResponse.new(
      [tool_use],
      "msg_123",
      "claude-3-5-sonnet",
      "assistant",
      Crig::Providers::Anthropic::Usage.new(0_i64, 0_i64),
      "end_turn",
    )
    response.text_response.should be_nil
  end
end
