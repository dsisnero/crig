require "../../spec_helper"

describe Crig::Completion::Message do
  it "exposes the system helper with System role" do
    message = Crig::Completion::Message.system("You are concise.")

    message.role.system?.should be_true
    message.rag_text.should eq("You are concise.")
  end
end
