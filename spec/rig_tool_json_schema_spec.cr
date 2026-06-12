require "./spec_helper"
require "json-schema"

Crig.rig_tool(
  description: "Perform basic arithmetic operations",
  params: {
    a:         "First number in the calculation",
    b:         "Second number in the calculation",
    op:        "The operation to perform (add, subtract, multiply, divide)",
  },
  required: [:a, :b, :op]
) do
  def calc(a : Int32, b : Int32, op : String) : Crig::ToolMacro::Result(Int32, Crig::ToolError)
    case op
    when "add" then Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(a + b)
    when "subtract" then Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(a - b)
    when "multiply" then Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(a * b)
    when "divide"
      if b == 0
        Crig::ToolMacro::Result(Int32, Crig::ToolError).err(Crig::ToolError.new("ToolCallError: Division by zero"))
      else
        Crig::ToolMacro::Result(Int32, Crig::ToolError).ok(a // b)
      end
    else
      Crig::ToolMacro::Result(Int32, Crig::ToolError).err(Crig::ToolError.new("ToolCallError: Unknown operation: #{op}"))
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
    tool = Calc.new
    definition = tool.definition("")

    # Core schema structure
    definition.parameters["type"].as_s.should eq("object")
    definition.parameters.as_h.has_key?("properties").should be_true

    props = definition.parameters["properties"].as_h
    props.has_key?("a").should be_true
    props.has_key?("b").should be_true
    props.has_key?("op").should be_true

    required = definition.parameters["required"].as_a.map(&.as_s)
    required.includes?("a").should be_true
    required.includes?("b").should be_true
    required.includes?("op").should be_true
  end

  it "synthesizes descriptions from params map" do
    tool = Calc.new
    definition = tool.definition("")

    definition.parameters["properties"]["a"]["description"].as_s.should eq("First number in the calculation")
    definition.parameters["properties"]["op"]["description"].as_s.should eq("The operation to perform (add, subtract, multiply, divide)")
  end

  it "synthesizes descriptions from params map" do
    tool = Calc.new
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
