require "../src/crig"

# =============================================================================
# Agent Run Stepping Example
# Ported from vendor/rig/examples/agent_run_stepping/src/main.rs
#
# Demonstrates two complementary ways to drive the agent loop:
#   1. Hand-driven AgentRun state machine (low-level control)
#   2. High-level AgentRunner with hooks (observability + steering)
#
# Uses DeepSeek as the LLM provider.
# Requires DEEPSEEK_API_KEY environment variable.
# =============================================================================

# A simple tool that adds two numbers.
struct AddTool
  include Crig::ToolDyn

  def name : String
    "add"
  end

  def definition(prompt : String) : Crig::Completion::ToolDefinition
    Crig::Completion::ToolDefinition.new(
      "add",
      "Add x and y together",
      JSON.parse(%({
        "type": "object",
        "properties": {
          "x": { "type": "number", "description": "The first number to add" },
          "y": { "type": "number", "description": "The second number to add" }
        },
        "required": ["x", "y"]
      })),
    )
  end

  def call(args : String) : String
    parsed = JSON.parse(args)
    x = parsed["x"].as_i
    y = parsed["y"].as_i
    (x + y).to_s
  end
end

# A LoggerHook that prints every tool call observed by the runner.
struct ToolLoggerHook
  include Crig::AgentHook

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    if event.tool_call?
      puts "[hook] tool call: #{event.tool_name}(#{event.args})"
    end
    Crig::Flow.cont
  end
end

# =============================================================================
# Part 1 — Hand-driven AgentRun state machine
# =============================================================================

puts "=== Part 1: Hand-driven AgentRun ==="
puts

client = Crig::Providers::DeepSeek::Client.from_env
model_name = Crig::Providers::DeepSeek::DEEPSEEK_CHAT

agent = client.agent(model_name)
  .preamble("You are a calculator. Always use the provided tools to compute results.")
  .tool(AddTool.new)
  .build

tool_def = AddTool.new.definition("")
ts_handle = agent.tool_server_handle.not_nil!
completion_model = client.completion_model(model_name)

run = Crig::AgentRun.new(Crig::Completion::Message.user("What is 2 + 5?")).max_turns(2)

loop do
  step = run.next_step
  case step.kind
  in .call_model?
    turn = step.turn.not_nil!
    prompt = step.prompt.not_nil!
    history = step.history.not_nil!

    puts "-> model call ##{turn}"
    builder = agent.completion(prompt, history)
    response = completion_model.completion(builder.build)

    turn_data = Crig::ModelTurn.new(
      choice: response.choice,
      usage: response.usage,
      allowed_tools: [tool_def.name],
    )
    outcome = run.model_response(turn_data)

    while outcome.kind.needs_resolution?
      ctx = outcome.context.not_nil!
      STDERR.puts "model called unknown tool `#{ctx.tool_name}`"
      outcome = run.resolve_invalid_tool_call(Crig::InvalidToolCallHookAction.fail)
    end
  in .call_tools?
    calls = step.calls.not_nil!
    results = [] of Crig::Completion::UserContent

    calls.each do |call|
      if pr = call.preresolved_result
        results << pr
        next
      end
      name = call.tool_call.function.name
      args = call.tool_call.function.arguments.to_json
      puts "-> executing #{name}(#{args})"
      output = ts_handle.call_tool(name, args)
      results << Crig::Completion::UserContent.tool_result(
        call.tool_call.id,
        Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
          Crig::Completion::ToolResultContent.text(output),
        ),
      )
    end

    run.tool_results(results)
  in .done?
    response = step.response.not_nil!
    puts "Done: #{response.output}"
    puts "  #{response.completion_calls.size} model call(s), #{response.usage.total_tokens} total tokens"
    break
  end
end

# =============================================================================
# Part 2 — High-level AgentRunner with hooks
# =============================================================================

puts
puts "=== Part 2: AgentRunner with ToolLoggerHook ==="
puts

agent2 = Crig::Agent(typeof(completion_model)).new(completion_model,
  preamble: "You are a calculator. Always use the provided tools to compute results.",
  tool_server_handle: ts_handle,
)

runner = agent2.runner(Crig::Completion::Message.user("What is 2 + 5?"))
  .max_turns(2)
  .add_hook(ToolLoggerHook.new)

response = runner.run(Crig::Completion::Message.user("What is 2 + 5?"))
puts "Done: #{response.output}"
puts "  #{response.completion_calls.size} model call(s), #{response.usage.total_tokens} total tokens"
