require "../spec_helper"

# Hook that stops the run after the add tool returns, with a portable reason.
class StopAfterResultHook
  include Crig::AgentHook

  def initialize(@reason : String)
  end

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    Crig::Flow.cont
  end

  def on_tool_result(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::ToolResultAction
    if event.tool_name == "add"
      Crig::ToolResultAction.stop(@reason)
    else
      Crig::ToolResultAction.cont
    end
  end
end

# Model that always calls the add tool.
class AlwaysAddModel
  include Crig::Completion::CompletionModel

  getter calls = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @calls += 1
    choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(
      Crig::Completion::AssistantContent.tool_call_with_call_id("add_1", "add_1", "add", JSON.parse(%({"x":20,"y":22})))
    )
    Crig::Completion::CompletionResponse(String).new(choice, Crig::Completion::Usage.new, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [] of String
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
      .tool(Crig::Completion::ToolDefinition.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))))
  end
end

module Crig
  describe "cancellation_and_max_turns conformance" do
    it "fails with PromptCancelled when a result hook stops the run" do
      cancelled_calls = Atomic(Int32).new(0)
      add_tool = DynamicTool.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))) do |args, ctx|
        cancelled_calls.add(1)
        parsed = JSON.parse(args)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON::Any.new(parsed["x"].as_i + parsed["y"].as_i)))
      end

      model = AlwaysAddModel.new
      ts = ToolServer.new
      ts.add_tool(add_tool)
      agent = Agent(typeof(model)).new(model,
        preamble: "Use add for arithmetic; never calculate by hand.",
        temperature: 0.0,
        tool_server_handle: ts.run,
      )

      error = expect_raises(Crig::Completion::PromptError) do
        agent.runner(Completion::Message.user("Use add once to compute x=20 plus y=22."))
          .max_turns(2)
          .add_hook(StopAfterResultHook.new("portable result veto"))
          .run(Completion::Message.user("Use add once to compute x=20 plus y=22."))
      end

      Conformance.validate_cancelled_failure(error, "portable result veto", "add")
      cancelled_calls.get.should eq(1)
    end

    it "fails with MaxTurnsError when the turn budget is exhausted" do
      max_turn_calls = Atomic(Int32).new(0)
      add_tool = DynamicTool.new("add", "Add x and y together", JSON.parse(%({"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}))) do |args, ctx|
        max_turn_calls.add(1)
        parsed = JSON.parse(args)
        Tool::ToolResult.success(Tool::ToolOutput.json(JSON::Any.new(parsed["x"].as_i + parsed["y"].as_i)))
      end

      model = AlwaysAddModel.new
      ts = ToolServer.new
      ts.add_tool(add_tool)
      agent = Agent(typeof(model)).new(model,
        preamble: "Use add for arithmetic; never calculate by hand.",
        temperature: 0.0,
        tool_server_handle: ts.run,
      )

      error = expect_raises(Crig::Completion::PromptError) do
        agent.runner(Completion::Message.user("Use add once to compute x=20 plus y=22, then report the result."))
          .max_turns(1)
          .run(Completion::Message.user("Use add once to compute x=20 plus y=22, then report the result."))
      end

      Conformance.validate_max_turns_failure(error, 1)
      max_turn_calls.get.should eq(1)
    end
  end
end
