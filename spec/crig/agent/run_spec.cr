require "../../spec_helper"

# Top-level spec helpers (not inside module Crig so they're accessible from describe blocks)
def expect_call_model(run : Crig::AgentRun) : Crig::AgentRunStep
  step = run.next_step
  raise "expected CallModel, got #{step.kind}" unless step.call_model?
  step
end

def expect_call_tools(run : Crig::AgentRun) : Array(Crig::PendingToolCall)
  step = run.next_step
  raise "expected CallTools, got #{step.kind}" unless step.call_tools?
  step.calls.not_nil!
end

def expect_done(run : Crig::AgentRun) : Crig::PromptResponse
  step = run.next_step
  raise "expected Done, got #{step.kind}" unless step.done?
  step.response.not_nil!
end

def expect_continue(outcome : Crig::ModelTurnOutcome) : Bool
  raise "expected Continue, got #{outcome.kind}" unless outcome.kind.continue?
  outcome.response_hook_suppressed?
end

def expect_needs_resolution(outcome : Crig::ModelTurnOutcome) : Crig::InvalidToolCallContext
  raise "expected NeedsResolution, got #{outcome.kind}" unless outcome.kind.needs_resolution?
  outcome.context.not_nil!
end

module Crig
  def self.text_content(text : String) : Completion::AssistantContent
    Completion::AssistantContent.text(text)
  end

  def self.tool_call_content(id : String, name : String, args : String = "{}") : Completion::AssistantContent
    Completion::AssistantContent.tool_call(id, name, JSON.parse(args))
  end

  describe AgentRun do
    it "text only run completes in one turn" do
      run = AgentRun.new(Completion::Message.user("hello"))
      expect_call_model(run)
      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(text_content("hi")),
      ))
      expect_continue(outcome).should be_false
      response = expect_done(run)
      response.output.should contain("hi")
    end

    it "tool roundtrip threads history and usage" do
      run = AgentRun.new(Completion::Message.user("add 2 and 3")).max_turns(2)
      expect_call_model(run)

      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "add")),
        executable_tool_names: ["add"],
        allowed_tool_names: ["add"],
      ))
      expect_continue(outcome).should be_false

      calls = expect_call_tools(run)
      calls.size.should eq(1)
      calls[0].tool_call.function.name.should eq("add")

      run.tool_results([Completion::UserContent.tool_result("call_1",
        OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text("5")))])

      expect_call_model(run)
      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(text_content("the answer is 5")),
      ))
      expect_continue(outcome).should be_false
      expect_done(run)
    end

    it "max turns exhaustion returns max turns error" do
      run = AgentRun.new(Completion::Message.user("add things")).max_turns(2)
      expect_call_model(run)
      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "add")),
        executable_tool_names: ["add"],
        allowed_tool_names: ["add"],
      ))
      expect_continue(outcome)
      calls = expect_call_tools(run)
      run.tool_results([Completion::UserContent.tool_result("call_1",
        OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text("0")))])

      # Second roundtrip
      expect_call_model(run)
      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_2", "add")),
        executable_tool_names: ["add"],
        allowed_tool_names: ["add"],
      ))
      expect_continue(outcome)
      calls = expect_call_tools(run)
      run.tool_results([Completion::UserContent.tool_result("call_2",
        OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text("0")))])

      # Third roundtrip exhausts max_turns
      expect_raises(Crig::Completion::PromptError, "MaxTurnsExceeded: 2") do
        run.next_step
      end
    end

    it "done step is idempotent" do
      run = AgentRun.new(Completion::Message.user("hello"))
      expect_call_model(run)
      run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(text_content("hi")),
      ))
      expect_done(run)
      response = expect_done(run)
      response.should_not be_nil
    end

    it "empty tool results cancel the run" do
      run = AgentRun.new(Completion::Message.user("add things")).max_turns(2)
      expect_call_model(run)
      run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "add")),
        executable_tool_names: ["add"],
        allowed_tool_names: ["add"],
      ))
      expect_call_tools(run)

      expect_raises(Crig::Completion::PromptError) do
        run.tool_results([] of Completion::UserContent)
      end
    end

    it "out of protocol calls are rejected without corrupting state" do
      run = AgentRun.new(Completion::Message.user("hello"))

      expect_raises(Crig::Completion::PromptError) do
        run.tool_results([Completion::UserContent.tool_result("call_1",
          OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text("x")))])
      end

      expect_call_model(run)
      expect_raises(Crig::Completion::PromptError) do
        run.next_step
      end
      run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(text_content("hi")),
      ))
      response = expect_done(run)
      response.output.should contain("hi")
    end

    it "output tool call finalizes run with arguments" do
      run = AgentRun.new(Completion::Message.user("get weather"))
        .with_output_tool_name("final_result")
      expect_call_model(run)

      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(
          tool_call_content("call_1", "final_result", %({"city":"Denver","temp":72})),
        ),
        executable_tool_names: ["final_result"],
        allowed_tool_names: ["final_result"],
      ))
      expect_continue(outcome)

      response = expect_done(run)
      response.should_not be_nil
    end

    it "invalid tool call fail returns unknown tool call error" do
      run = AgentRun.new(Completion::Message.user("call unknown")).max_turns(2)
      expect_call_model(run)

      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "unknown_tool")),
        executable_tool_names: ["add"],
        allowed_tool_names: ["add"],
      ))
      ctx = expect_needs_resolution(outcome)
      ctx.tool_name.should eq("unknown_tool")

      error = expect_raises(Crig::Completion::PromptError) do
        run.resolve_invalid_tool_call(Crig::InvalidToolCallHookAction.fail)
      end

      Crig::Conformance.validate_unknown_tool_failure(error, "unknown_tool", ["add"])
    end

    it "invalid tool call retry rolls back with feedback" do
      run = AgentRun.new(Completion::Message.user("call unknown")).max_turns(2)
        .max_invalid_tool_call_retries(1)
      expect_call_model(run)

      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "unknown_tool")),
        executable_tool_names: ["add"],
        allowed_tool_names: ["add"],
      ))
      expect_needs_resolution(outcome)

      result = run.resolve_invalid_tool_call(Crig::InvalidToolCallHookAction.retry("try add"))
      result.kind.turn_retried?.should be_true
      expect_call_model(run)
    end

    it "invalid tool call repair renames and suppresses response hook" do
      run = AgentRun.new(Completion::Message.user("call mispelled")).max_turns(2)
      expect_call_model(run)

      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "ad")),
        executable_tool_names: ["add"],
        allowed_tool_names: ["add"],
      ))
      expect_needs_resolution(outcome)

      result = run.resolve_invalid_tool_call(Crig::InvalidToolCallHookAction.repair("add"))
      suppressed = expect_continue(result)
      suppressed.should be_true

      calls = expect_call_tools(run)
      calls[0].tool_call.function.name.should eq("add")
    end

    it "exposes usage, response, and is_done after completion" do
      run = AgentRun.new(Completion::Message.user("hello"))
      expect_call_model(run)
      run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(text_content("hi")),
        usage: Completion::Usage.new(input_tokens: 5, output_tokens: 2, total_tokens: 7),
      ))
      response = expect_done(run)

      run.is_done.should be_true
      run.done?.should be_true
      run.usage.total_tokens.should eq(7)
      run.usage.input_tokens.should eq(5)
      run.response.should_not be_nil
      run.response.not_nil!.output.should eq(response.output)
    end

    it "exposes usage before completion" do
      run = AgentRun.new(Completion::Message.user("hello"))
      run.usage.total_tokens.should eq(0)
      expect_call_model(run)
      run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(text_content("hi")),
        usage: Completion::Usage.new(total_tokens: 3),
      ))
      run.usage.total_tokens.should eq(3)
    end

    it "builds a cancellation error carrying full history" do
      run = AgentRun.new(Completion::Message.user("hello"))
      error = run.cancel_error("user cancelled")

      error.should be_a(Completion::PromptError)
      error.to_s.should contain("user cancelled")
    end

    it "returns nil for pending invalid tool call when none is awaiting resolution" do
      run = AgentRun.new(Completion::Message.user("hello"))
      expect_call_model(run)
      run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(text_content("hi")),
      ))
      expect_done(run)

      run.pending_invalid_tool_call.should be_nil
    end

    it "reports the pending invalid tool call while awaiting resolution" do
      run = AgentRun.new(Completion::Message.user("call mispelled")).max_turns(2)
      expect_call_model(run)

      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "ad")),
        executable_tool_names: ["add"],
        allowed_tool_names: ["add"],
      ))
      expect_needs_resolution(outcome)

      pending = run.pending_invalid_tool_call
      pending.should_not be_nil
      pending.not_nil!.tool_name.should eq("ad")
      pending.not_nil!.tool_call_id.should eq("call_1")
    end
  end
end
