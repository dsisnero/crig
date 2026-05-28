require "./spec_helper"

struct NullArgsNormalized
  include JSON::Serializable
  getter label : String?
end

struct NoArgTool
  include Crig::Tool(NullArgsNormalized, String)

  def name : String
    "no_arg_tool"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "no_arg_tool",
      "Tool with no required arguments",
      JSON.parse(%({"type":"object","properties":{}}))
    )
  end

  def call_typed(args : NullArgsNormalized) : String
    args.label || "default"
  end
end

struct AnyArgsTool
  include Crig::Tool(JSON::Any, String)

  def name : String
    "any_args_tool"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "any_args_tool",
      "Tool with raw JSON args",
      JSON.parse(%({"type":"object","properties":{}}))
    )
  end

  def call_typed(args : JSON::Any) : String
    if args.raw.is_a?(Nil)
      "null_accepted"
    else
      args.to_json
    end
  end
end

describe Crig::ToolDyn do
  it "normalizes null args to empty object for all-optional structs" do
    tool = NoArgTool.new
    output = tool.call("null")
    output.should eq(%("default"))
  end

  it "preserves null args for types that accept null" do
    tool = AnyArgsTool.new
    output = tool.call("null")
    output.should eq(%("null_accepted"))
  end
end
