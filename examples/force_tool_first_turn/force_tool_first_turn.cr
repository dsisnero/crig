require "../../src/crig"

PREAMBLE = "You are a calculator assistant. Use the add tool for arithmetic, then report the result."
PROMPT   = "What is 21 + 21? Use the add tool, then tell me the answer."

struct AddArgs
  include JSON::Serializable
  getter x : Int64
  getter y : Int64

  def initialize(@x : Int64, @y : Int64)
  end
end

struct Add
  include Crig::Tool(AddArgs, Int64)

  NAME = "add"

  def description : String
    "Add x and y together"
  end

  def parameters : JSON::Any
    JSON.parse(%({"type":"object","properties":{"x":{"type":"number","description":"The first addend"},"y":{"type":"number","description":"The second addend"}},"required":["x","y"]}))
  end

  def call_typed(args : AddArgs) : Int64
    args.x + args.y
  end
end

struct ForceToolEveryTurn
  include Crig::AgentHook

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    if event.kind.completion_call?
      Crig::Flow.patch_request(Crig::RequestPatch.new.tool_choice(Crig::Completion::ToolChoice.required))
    else
      Crig::Flow.cont
    end
  end
end

struct ForceToolOnFirstTurn
  include Crig::AgentHook

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    if event.kind.completion_call? && ctx.turn == 1
      Crig::Flow.patch_request(Crig::RequestPatch.new.tool_choice(Crig::Completion::ToolChoice.required))
    else
      Crig::Flow.cont
    end
  end
end

client = Crig::Providers::OpenAI::Client.from_env

make_agent = -> {
  client.agent(Crig::Providers::OpenAI::GPT_4O)
    .preamble(PREAMBLE)
    .tool(Add.new)
    .build
}

puts "=== forcing tool_choice=Required on EVERY turn (the footgun) ==="
agent = make_agent.call
result = agent.prompt(PROMPT).max_turns(4).with_hook(ForceToolEveryTurn.new).send
puts "result: #{result}"

puts "\n=== forcing tool_choice=Required on the FIRST turn only (the fix) ==="
agent = make_agent.call
result = agent.prompt(PROMPT).max_turns(4).with_hook(ForceToolOnFirstTurn.new).send
puts "final answer: #{result}"
