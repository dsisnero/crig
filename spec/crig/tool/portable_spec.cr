require "../../spec_helper"

module Crig::Tool
  describe PortableDynamicTool do
    it "executes callback with owned arguments" do
      tool = PortableDynamicTool.new(
        "echo",
        "Echo a JSON value",
        JSON.parse(%({"type": "object"})),
      ) do |arguments|
        ToolOutput.json(arguments)
      end

      arguments = JSON.parse(%({"value": "hello"}))
      output = tool.execute(arguments)
      output.as_json.should eq(arguments)
    end

    it "reports its name and definition" do
      tool = PortableDynamicTool.new(
        "add",
        "Add two integers",
        JSON.parse(%({"type": "object", "properties": {"a": {"type": "integer"}}})),
      ) do |arguments|
        ToolOutput.text("ok")
      end

      tool.name.should eq("add")
      defn = tool.definition
      defn.name.should eq("add")
      defn.description.should eq("Add two integers")
    end
  end
end
