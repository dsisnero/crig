require "../spec_helper"

module Crig
  describe "AgentBuilder tool API" do
    it "repeated .tool() registers multiple tools" do
      model = FakeCompletionModel.new
      t1 = Completion::ToolDefinition.new("tool_a", "Tool A", JSON.parse(%({"type":"object"})))
      t2 = Completion::ToolDefinition.new("tool_b", "Tool B", JSON.parse(%({"type":"object"})))
      builder = AgentBuilder(typeof(model)).new(model)
        .tool(t1)
        .tool(t2)
      agent = builder.build
      agent.static_tools.size.should eq(2)
    end

    it ".tools(Vec) still works for backward compat" do
      model = FakeCompletionModel.new
      tools = [
        Completion::ToolDefinition.new("tool_a", "Tool A", JSON.parse(%({"type":"object"}))),
        Completion::ToolDefinition.new("tool_b", "Tool B", JSON.parse(%({"type":"object"}))),
      ]
      builder = AgentBuilder(typeof(model)).new(model).tools(tools)
      agent = builder.build
      agent.static_tools.size.should eq(2)
    end

    it ".tool and .tools produce equivalent static_tools" do
      model = FakeCompletionModel.new
      model2 = FakeCompletionModel.new
      t1 = Completion::ToolDefinition.new("tool_a", "Tool A", JSON.parse(%({"type":"object"})))
      t2 = Completion::ToolDefinition.new("tool_b", "Tool B", JSON.parse(%({"type":"object"})))
      builder1 = AgentBuilder(typeof(model)).new(model).tool(t1).tool(t2)
      builder2 = AgentBuilder(typeof(model2)).new(model2).tools([t1, t2])
      agent1 = builder1.build
      agent2 = builder2.build
      agent1.static_tools.map(&.name).should eq(agent2.static_tools.map(&.name))
    end
  end
end
