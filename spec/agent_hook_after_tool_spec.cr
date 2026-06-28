require "./spec_helper"

class HookProbe < Crig::PromptHook
  getter call_log : Array(String)

  def initialize
    @call_log = [] of String
  end

  def on_completion_call(prompt : Crig::Completion::Message, history : Array(Crig::Completion::Message)) : Crig::HookAction
    @call_log << "completion_call"
    Crig::HookAction.cont
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

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "echo",
      "Echo the given value",
      JSON.parse(%({"type":"object"}))
    )
  end

  def call_typed(args : ToolArgs) : String
    args.value
  end
end

describe "Agent hook after tool builder chaining" do
  it "allows .tool(...).hook(...) chaining and applies hook to prompt requests" do
    model = FakeCompletionModel.new
    probe = HookProbe.new
    echo = EchoTool2.new

    agent = Crig::AgentBuilder(typeof(model)).new(model)
      .name("test")
      .tool(echo)
      .hook(probe)
      .build

    agent.hook.should eq(probe)

    request = agent.prompt("hello")
    request.hook.should eq(probe)

    stream_request = agent.stream_prompt("hello")
    stream_request.hook.should eq(probe)

    # Verify hook can be overridden per-request
    other_probe = HookProbe.new
    overridden = request.with_hook(other_probe)
    overridden.hook.should eq(other_probe)
  end
end
