require "./spec_helper"

class RecordingHook
  include Crig::AgentHook

  getter events : Array(String)

  def initialize
    @events = [] of String
  end

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    @events << event.kind.to_s
    Crig::Flow.cont
  end
end

struct ToolArgs
  include JSON::Serializable
  getter value : String

  def initialize(@value : String)
  end
end

struct EchoTool2
  include Crig::Tool(ToolArgs, String)

  def name : String
    "echo"
  end

  def description : String
    "Echo the given value"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object"}))
  end

  def call_typed(args : ToolArgs) : String
    args.value
  end
end

describe "Agent hook after tool builder chaining" do
  it "allows .tool(...).hook(...) chaining and applies hook to prompt requests" do
    model = FakeCompletionModel.new
    probe = RecordingHook.new
    echo = EchoTool2.new

    agent = Crig::AgentBuilder(typeof(model)).new(model)
      .name("test")
      .tool(echo)
      .hook(probe)
      .build

    request = agent.prompt("hello")
    request.runner.add_hook(probe)

    stream_request = agent.stream_prompt("hello")
    stream_request.with_hook(probe)
  end
end
