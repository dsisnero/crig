require "../../../spec_helper"

def make_tool_msg(id : String, call_id : String, content)
  Crig::Completion::Message.user(
    Crig::Completion::UserContent.tool_result_with_call_id(id, call_id, content)
  )
end

module Crig::Providers::OpenAI
  describe "multipart tool results" do
    it "single text tool result sends as string output" do
      text = Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
        Crig::Completion::ToolResultContent.text("plain result")
      )
      msg = make_tool_msg("t1", "call_1", text)
      items = InputItem.from_completion_message(msg)
      items.size.should eq(1)
      json = items.first.to_json_value
      json["type"].as_s.should eq("function_call_output")
      json["call_id"].as_s.should eq("call_1")
      json["output"].as_s.should eq("plain result")
    end

    it "multipart tool result preserves multiple text blocks" do
      blocks = Crig::OneOrMany(Crig::Completion::ToolResultContent).many([
        Crig::Completion::ToolResultContent.text("first block"),
        Crig::Completion::ToolResultContent.text("second block"),
      ])
      msg = make_tool_msg("t2", "call_2", blocks)
      items = InputItem.from_completion_message(msg)
      items.size.should eq(1)
      json = items.first.to_json_value
      json["type"].as_s.should eq("function_call_output")
      json["call_id"].as_s.should eq("call_2")
      output = json["output"]
      output.as_a?.should be_truthy
      texts = output.as_a.map { |v| v["text"].as_s }
      texts.should eq(["first block", "second block"])
    end
  end
end
