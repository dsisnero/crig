require "../../spec_helper"

module Crig::Completion
  describe UserContent, "convenience constructors" do
    it "tool_result(id, text) wraps plain string" do
      r = UserContent.tool_result("call_1", "hello world")
      r.kind.tool_result?.should be_true
      tr = r.tool_result.not_nil!
      tr.id.should eq("call_1")
      c = tr.content.first.as(ToolResultContent)
      c.text.not_nil!.text.should eq("hello world")
    end

    it "tool_result(id, text) matches verbose version" do
      verbose = UserContent.tool_result("x",
        Crig::OneOrMany(ToolResultContent).one(ToolResultContent.text("hi")))
      concise = UserContent.tool_result("x", "hi")
      verbose.tool_result.not_nil!.id.should eq(concise.tool_result.not_nil!.id)
    end

    it "tool_result_with_call_id(id, call_id, text) wraps plain string" do
      r = UserContent.tool_result_with_call_id("call_1", "prov_abc", "result")
      tr = r.tool_result.not_nil!
      tr.id.should eq("call_1")
      tr.call_id.should eq("prov_abc")
      tr.content.first.as(ToolResultContent).text.not_nil!.text.should eq("result")
    end
  end
end
