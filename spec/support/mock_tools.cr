require "../spec_helper"

# Mock tools ported from rig-agent/test_utils/tools.rs for deterministic tests.

# A caller-injected context value, like a session id or auth token carried in
# a ToolContext (upstream `SessionId`).
struct SessionId
  include JSON::Serializable

  getter value : String

  def initialize(@value : String)
  end
end

# Arguments for arithmetic mock tools (upstream `MockOperationArgs`).
struct MockOperationArgs
  include JSON::Serializable

  getter x : Int32
  getter y : Int32

  def initialize(@x : Int32, @y : Int32)
  end
end

# A mock tool that adds `x` and `y` (upstream `MockAddTool`).
struct MockAddTool
  include Crig::Tool(MockOperationArgs, Int32)

  def name : String
    "add"
  end

  def description : String
    "Add x and y together"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object","properties":{"x":{"type":"number","description":"The first number to add"},"y":{"type":"number","description":"The second number to add"}},"required":["x","y"]}))
  end

  def call_typed(args : MockOperationArgs) : Int32
    args.x + args.y
  end
end

# A mock tool that subtracts `y` from `x` (upstream `MockSubtractTool`).
struct MockSubtractTool
  include Crig::Tool(MockOperationArgs, Int32)

  def name : String
    "subtract"
  end

  def description : String
    "Subtract y from x"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object","properties":{"x":{"type":"number","description":"The number to subtract from"},"y":{"type":"number","description":"The number to subtract"}},"required":["x","y"]}))
  end

  def call_typed(args : MockOperationArgs) : Int32
    args.x - args.y
  end
end

# A toolset containing MockAddTool and MockSubtractTool (upstream `mock_math_toolset`).
def mock_math_toolset : Crig::ToolSet
  toolset = Crig::ToolSet.new
  toolset.add_tool(MockAddTool.new)
  toolset.add_tool(MockSubtractTool.new)
  toolset
end

# A mock tool that records whatever SessionId it observed in its per-call
# ToolContext (upstream `MockContextProbeTool`).
class MockContextProbeTool
  include Crig::ToolDyn

  getter observed : String?

  @observations : Array(String) = [] of String

  def name : String
    "context_probe"
  end

  def description : String
    "Records the SessionId observed in its call context"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object","properties":{}}))
  end

  def call(args : String) : String
    execute(args, Crig::Tool::ToolContext.new).output.render
  end

  def execute(args : String, context : Crig::Tool::ToolContext) : Crig::Tool::ToolResult
    value = context.get(SessionId)
    rendered = if session = value
                 "session:#{session.value}"
               else
                 "no-session"
               end
    @observations << rendered
    @observed = rendered
    Crig::Tool::ToolResult.success(Crig::Tool::ToolOutput.text(rendered))
  end

  def observations : Array(String)
    @observations.dup
  end
end
