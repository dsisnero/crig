require "../../spec_helper"

module Crig
  describe DynamicTool do
    it "executes callback and returns ToolResult" do
      tool = DynamicTool.new("echo", "Echo input", JSON.parse(%({"type":"string"}))) do |args, ctx|
        Tool::ToolResult.success(Tool::ToolOutput.text(args))
      end

      tool.name.should eq("echo")
      tool.description.should eq("Echo input")

      result = tool.execute("hello", Tool::ToolContext.new)
      result.success?.should be_true
      result.output.as_text.should eq("hello")
    end

    it "exposes tool definition" do
      tool = DynamicTool.new("add", "Add numbers", JSON.parse(%({"type":"object"}))) do |args, ctx|
        Tool::ToolResult.success(Tool::ToolOutput.text(args))
      end

      defn = tool.definition
      defn.name.should eq("add")
      defn.description.should eq("Add numbers")
    end

    it "supports error returns" do
      tool = DynamicTool.new("fail", "Always fails", JSON.parse(%({"type":"object"}))) do |args, ctx|
        Tool::ToolResult.failed(Tool::ToolExecutionError.provider("something broke"))
      end

      result = tool.execute("{}", Tool::ToolContext.new)
      result.error?.should be_true
      result.error.should be_truthy
    end

    it "forwards ToolContext to callback" do
      tool = DynamicTool.new("ctx", "Check context", JSON.parse(%({"type":"object"}))) do |args, ctx|
        val = ctx.get(UInt32)
        Tool::ToolResult.success(Tool::ToolOutput.text(val.try(&.to_s) || "none"))
      end

      ctx = Tool::ToolContext.new
      ctx.insert(42_u32)
      result = tool.execute("{}", ctx)
      result.output.as_text.should eq("42")
    end
  end
end
