require "./spec_helper"

Crig.rig_tool description: "Add two numbers" do
  def add(x : Int32, y : Int32) : Int32
    x + y
  end
end

Crig.rig_tool do
  def greet(name : String, greeting : String?) : String
    "#{greeting || "Hello"}, #{name}"
  end
end

Crig.rig_tool do
  def optional_types(
    required_str : String,
    optional_str : String?,
    required_int : Int32,
    optional_int : Int32?,
    required_float : Float64,
    optional_float : Float64?,
    required_bool : Bool,
    optional_bool : Bool?,
  ) : String
    "ok"
  end
end

describe "Simplified rig_tool API" do
  it "generates tool definition using json-schema without params/required" do
    tool = Add.new
    definition = tool.definition("")
    definition.name.should eq("add")
    definition.description.should eq("Add two numbers")

    props = definition.parameters["properties"].as_h
    props.has_key?("x").should be_true
    props.has_key?("y").should be_true
    props["x"]["type"].as_s.should eq("integer")
    props["y"]["type"].as_s.should eq("integer")

    required = definition.parameters["required"].as_a.map(&.as_s)
    required.includes?("x").should be_true
    required.includes?("y").should be_true
  end

  it "allows optional tool description" do
    tool = Greet.new
    definition = tool.definition("")
    definition.name.should eq("greet")
    definition.description.should eq("Function to greet")
  end

  it "marks nilable fields as optional in required array" do
    tool = Greet.new
    definition = tool.definition("")
    required = definition.parameters["required"].as_a.map(&.as_s)
    required.includes?("name").should be_true
    required.includes?("greeting").should be_false
  end

  it "calls tool with valid args" do
    tool = Add.new
    result = tool.call(%({"x":2,"y":3}))
    result.should eq("5")
  end

  it "calls tool with optional args omitted" do
    tool = Greet.new
    result = tool.call(%({"name":"World"}))
    result.should eq(%("Hello, World"))
  end

  it "generates correct json-schema for all nilable types" do
    tool = OptionalTypes.new
    definition = tool.definition("")
    props = definition.parameters["properties"].as_h
    required = definition.parameters["required"].as_a.map(&.as_s)

    # Non-nilable fields are required
    required.includes?("required_str").should be_true
    required.includes?("required_int").should be_true
    required.includes?("required_float").should be_true
    required.includes?("required_bool").should be_true

    # Nilable fields are optional
    required.includes?("optional_str").should be_false
    required.includes?("optional_int").should be_false
    required.includes?("optional_float").should be_false
    required.includes?("optional_bool").should be_false

    # Nilable float: anyOf contains null and number
    types = props["optional_float"]["anyOf"].as_a.map { |v| v["type"].as_s }
    types.includes?("null").should be_true
    types.includes?("number").should be_true
  end
end
