require "./spec_helper"

struct CrigToolTSArgs
  include JSON::Serializable
  getter value : String
  def initialize(@value : String)
  end
end

struct EchoToolTS
  include Crig::Tool(CrigToolTSArgs, String)

  def name : String
    "echo"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new("echo", "echoes", JSON.parse(%({"type":"object"})))
  end

  def call_typed(args : CrigToolTSArgs) : String
    args.value
  end
end

describe "ToolServer append_toolset tool visibility" do
  it "extends static tool names when appending a toolset" do
    tool_a = Crig::ToolSet.from_tools([EchoToolTS.new])
    tool_b = Crig::ToolSet.from_tools([Crig::ThinkTool.new])

    server = Crig::ToolServer.new
    server.add_tool(EchoToolTS.new)

    before = server.visible_tool_names
    before.should contain("echo")

    server.append_toolset(tool_a)
    server.append_toolset(tool_b)

    after = server.visible_tool_names
    after.should contain("echo")
    after.should contain("think")
  end
end
