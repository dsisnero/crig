require "./spec_helper"

describe "Message::System exhaustive case coverage" do
  it "gemini completion raises error for System messages" do
    msg = Crig::Completion::Message.system("instruction")
    expect_raises(Crig::Completion::CompletionError, /System messages/) do
      Crig::Providers::Gemini::Content.from_message(msg)
    end
  end

  it "anthropic converts System messages to Anthropic Content" do
    msg = Crig::Completion::Message.system("Be helpful.")
    anthropic_msg = Crig::Providers::Anthropic::Message.from_core_message(msg)
    anthropic_msg.role.system?.should be_true
  end
end
