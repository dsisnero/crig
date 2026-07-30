require "../../spec_helper"

module Crig
  describe ToolSet do
    it "execute returns ToolResult for successful call" do
      ts = ToolSet.from_tools([SimpleEchoTool.new])
      result = ts.execute("echo", "hello", Tool::ToolContext.new)
      result.success?.should be_true
      result.output.as_text.should eq("hello")
    end

    it "execute returns ToolResult for missing tool" do
      ts = ToolSet.new
      result = ts.execute("nope", "{}", Tool::ToolContext.new)
      result.error?.should be_true
      result.error.try(&.kind).should eq(Tool::ToolErrorKind::NotFound)
    end

    it "execute wraps ToolDyn call errors in ToolResult" do
      tool = CrashingTool.new
      ts = ToolSet.new
      ts.add_tool(tool)

      result = ts.execute("crash", "{}", Tool::ToolContext.new)
      result.error?.should be_true
    end
  end

  struct SimpleEchoTool
    include ToolDyn

    def name : String
      "echo"
    end

    def description : String
      "Echo"
    end

    def parameters : JSON::Any
      JSON.parse(%({"type":"string"}))
    end

    def call(args : String) : String
      args
    end
  end

  struct CrashingTool
    include ToolDyn

    def name : String
      "crash"
    end

    def description : String
      "Crash"
    end

    def parameters : JSON::Any
      JSON.parse(%({"type":"string"}))
    end

    def call(args : String) : String
      raise "boom"
    end
  end
end
