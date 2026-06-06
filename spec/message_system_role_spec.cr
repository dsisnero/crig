require "./spec_helper"

describe "Message::System role" do
  it "creates system messages" do
    msg = Crig::Completion::Message.system("Be helpful.")
    msg.role.system?.should be_true
    msg.rag_text.should eq("Be helpful.")
  end

  it "round-trips in a chat history" do
    history = [
      Crig::Completion::Message.system("Instruction"),
      Crig::Completion::Message.user("Hello"),
      Crig::Completion::Message.assistant("Hi there"),
    ]
    history[0].role.system?.should be_true
    history[1].role.user?.should be_true
    history[2].role.assistant?.should be_true
  end
end
