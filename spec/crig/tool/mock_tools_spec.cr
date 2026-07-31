require "../../spec_helper"

module Crig
  describe MockAddTool do
    it "adds x and y" do
      tool = MockAddTool.new
      tool.name.should eq("add")
      tool.description.should eq("Add x and y together")

      tool.call(%({"x":2,"y":5})).should eq("7")
    end
  end

  describe MockSubtractTool do
    it "subtracts y from x" do
      tool = MockSubtractTool.new
      tool.name.should eq("subtract")

      tool.call(%({"x":5,"y":2})).should eq("3")
    end
  end

  describe "mock_math_toolset" do
    it "registers add and subtract tools" do
      toolset = mock_math_toolset

      toolset.contains("add").should be_true
      toolset.contains("subtract").should be_true
      toolset.call("add", %({"x":2,"y":5})).should eq("7")
      toolset.call("subtract", %({"x":5,"y":2})).should eq("3")
    end
  end

  describe MockContextProbeTool do
    it "records the SessionId observed in its call context" do
      tool = MockContextProbeTool.new
      context = Tool::ToolContext.new
      context.insert(SessionId.new("abc-123"))

      result = tool.execute(%({}), context)
      result.success?.should be_true
      result.output.render.should eq("session:abc-123")

      tool.observed.should eq("session:abc-123")
    end

    it "reports no-session when the context has no SessionId" do
      tool = MockContextProbeTool.new
      context = Tool::ToolContext.new

      result = tool.execute(%({}), context)
      result.success?.should be_true
      result.output.render.should eq("no-session")

      tool.observed.should eq("no-session")
      tool.observations.should eq(["no-session"])
    end
  end
end
