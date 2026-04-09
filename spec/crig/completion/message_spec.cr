require "../../spec_helper"

describe Crig::Completion::Message do
  it "exposes the system helper as a legacy user-shaped prompt message" do
    message = Crig::Completion::Message.system("You are concise.")

    message.role.user?.should be_true
    message.rag_text.should eq("You are concise.")
  end
end
