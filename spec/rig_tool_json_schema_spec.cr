require "./spec_helper"
require "json-schema"

Crig.rig_tool(
  description: "Perform basic arithmetic operations",
  params: {
    x:         "First number in the calculation",
    y:         "Second number in the calculation",
    operation: "The operation to perform (add, subtract, multiply, divide)",
  },
  required: [:x, :y, :operation]
) do
  def calculator(x : Int32, y : Int32, operation : String) : Crig::ToolMacro::Result(Int32, Crig::ToolError)
    case operation
    when "add" then Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x + y)
    when "subtract" then Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x - y)
    when "multiply" then Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x * y)
    when "divide"
      if y == 0
        Crig::ToolMacro::Result(Int32, Crig::ToolError).err(Crig::ToolError.new("ToolCallError: Division by zero"))
      else
        Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(x // y)
      end
    else
      Crig::ToolMacro::Result(Int32, Crig::ToolError).err(Crig::ToolError.new("ToolCallError: Unknown operation: #{operation}"))
    end
  end
end

Crig.rig_tool do
  def optional_tool(x : Int32, label : String?) : Crig::ToolMacro::Result(String, Crig::ToolError)
    Crig::ToolMacro::Result(String, Crig::ToolError).ok(label || "default")
  end
end

describe "rig_tool json-schema integration" do
  it "generates schema matching json-schema output format" do
    tool = Calculator.new
    definition = tool.definition("")

    # Core schema structure
    definition.parameters["type"].as_s.should eq("object")
    definition.parameters.as_h.has_key?("properties").should be_true

    # Properties exist for all params
    props = definition.parameters["properties"].as_h
    props.has_key?("x").should be_true
    props.has_key?("y").should be_true
    props.has_key?("operation").should be_true

    # Required fields
    required = definition.parameters["required"].as_a.map(&.as_s)
    required.includes?("x").should be_true
    required.includes?("y").should be_true
    required.includes?("operation").should be_true
  end

  it "synthesizes descriptions from params map" do
    tool = Calculator.new
    definition = tool.definition("")

    definition.parameters["properties"]["x"]["description"].as_s.should eq("First number in the calculation")
    definition.parameters["properties"]["operation"]["description"].as_s.should eq("The operation to perform (add, subtract, multiply, divide)")
  end

  it "outputs nilable fields as non-required" do
    tool = OptionalTool.new
    definition = tool.definition("")
    required = definition.parameters["required"].as_a.map(&.as_s)
    required.includes?("x").should be_true
    required.includes?("label").should be_false
  end
end
