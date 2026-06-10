require "./spec_helper"

describe "Anthropic System message from_core_message round-trip" do
  it "converts System messages to Anthropic Message with System role" do
    msg = Crig::Completion::Message.system("Be helpful.")
    anthropic = Crig::Providers::Anthropic::Message.from_core_message(msg)
    anthropic.role.system?.should be_true
    text_content = anthropic.content.find(&.kind.text?)
    text_content.should_not be_nil
    text_content.not_nil!.text.should eq("Be helpful.")
  end

  it "converts Anthropic System message back to Core System message" do
    system_content = Crig::Providers::Anthropic::Content.text("Be helpful.")
    anthropic = Crig::Providers::Anthropic::Message.new(
      Crig::Providers::Anthropic::Role::System,
      Crig::OneOrMany(Crig::Providers::Anthropic::Content).one(system_content),
    )
    core = anthropic.to_core_message
    core.role.system?.should be_true
    core.rag_text.should eq("Be helpful.")
  end

  it "round-trips System message through Anthropic conversion" do
    original = Crig::Completion::Message.system("Instruction.")
    anthropic = Crig::Providers::Anthropic::Message.from_core_message(original)
    core = anthropic.to_core_message
    core.role.system?.should be_true
    core.rag_text.should eq("Instruction.")
  end
end

