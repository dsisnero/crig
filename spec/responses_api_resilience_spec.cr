require "./spec_helper"

describe "OpenAI Responses API resilience fixes" do
  it "tolerates reasoning with missing ID" do
    reasoning = Crig::Completion::Reasoning.new([
      Crig::Completion::ReasoningContent.text("let me think"),
    ], nil)
    result = Crig::Providers::OpenAI::OpenAIReasoning.from_core(reasoning)
    result.should be_nil
  end

  it "tolerates missing assistant message ID" do
    msg = Crig::Completion::Message.assistant("response")
    items = Crig::Providers::OpenAI::InputItem.from_completion_message(msg)
    items.should_not be_empty
  end
end
