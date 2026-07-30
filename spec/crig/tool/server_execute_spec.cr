require "../../spec_helper"

module Crig
  describe ToolServerHandle do
    it "execute returns ToolResult for successful call" do
      tool = DynamicTool.new("greet", "Greets", JSON.parse(%({"type":"string"}))) do |args, ctx|
        Tool::ToolResult.success(Tool::ToolOutput.text("Hello #{args}"))
      end

      handle = ToolServerHandle.with_resolver("test", ->(name : String, args : String) { tool.call(args) })

      result = handle.execute("greet", "world", Tool::ToolContext.new)
      result.success?.should be_true
      result.output.as_text.should eq("Hello world")
    end

    it "execute returns ToolResult for failing call" do
      handle = ToolServerHandle.with_resolver("test", ->(name : String, args : String) { raise "not found" })

      result = handle.execute("nope", "{}", Tool::ToolContext.new)
      result.error?.should be_true
    end
  end
end
