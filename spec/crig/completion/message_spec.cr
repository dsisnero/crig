require "../../spec_helper"

describe Crig::Completion::Message do
  it "exposes the system helper with System role" do
    message = Crig::Completion::Message.system("You are concise.")

    message.role.system?.should be_true
    message.rag_text.should eq("You are concise.")
  end
end
describe Crig::Completion::Message, tags: %w[completion message] do
  it "builds a user message" do
    message = Crig::Completion::Message.user("hello")

    message.role.user?.should be_true
    message.rag_text.should eq("hello")
  end

  it "builds an assistant message with an id" do
    message = Crig::Completion::Message.assistant_with_id("assistant-1", "hi")

    message.role.assistant?.should be_true
    message.id.should eq("assistant-1")
  end

  it "builds a tool result message" do
    message = Crig::Completion::Message.tool_result_with_call_id("tool-1", "call-1", "done")
    content = message.content.first.as(Crig::Completion::UserContent)
    tool_result = content.tool_result
    tool_result.should_not be_nil
    text = tool_result.as(Crig::Completion::ToolResult).content.first.text
    text.should_not be_nil

    content.kind.tool_result?.should be_true
    tool_result.as(Crig::Completion::ToolResult).call_id.should eq("call-1")
    text.as(Crig::Completion::Text).text.should eq("done")
  end
end
