require "../spec_helper"

# Port of the invalid_tool_recovery scenario: drives the low-level AgentRun
# state machine with a model turn whose add call is disallowed (allowed=["sum"]),
# then exercises fail, retry-exhaustion, rejected repair, valid repair, and skip.

private def invalid_tool_recovery_prompt : String
  "Call the add tool exactly once with x=2 and y=3. Do not call sum."
end

private def disallowed_turn : Crig::ModelTurn
  choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(
    Crig::Completion::AssistantContent.tool_call_with_call_id(
      "add_1", "add_1", "add",
      JSON.parse(%({"x":2,"y":3})),
    )
  )
  Crig::ModelTurn.new(
    message_id: "msg-1",
    choice: choice,
    usage: Crig::Completion::Usage.new(input_tokens: 5, output_tokens: 2, total_tokens: 7),
    executable_tool_names: ["add", "sum"],
    allowed_tool_names: ["sum"],
  )
end

private def restricted_recovery_run(prompt : String, turn : Crig::ModelTurn, retries : Int32) : Crig::AgentRun
  run = Crig::AgentRun.new(prompt)
    .max_turns(2)
    .max_invalid_tool_call_retries(retries)

  step = run.next_step
  step.kind.call_model?.should be_true

  outcome = run.model_response(turn)
  outcome.kind.needs_resolution?.should be_true
  ctx = outcome.context
  ctx.should_not be_nil
  ctx.not_nil!.tool_name.should eq("add")

  run
end

module Crig
  describe "invalid_tool_recovery conformance" do
    it "fails fast on a disallowed tool call" do
      run = restricted_recovery_run(invalid_tool_recovery_prompt, disallowed_turn, 0)
      error = expect_raises(Crig::Completion::PromptError) do
        run.resolve_invalid_tool_call(Crig::InvalidToolCallHookAction.fail)
      end
      Conformance.validate_unknown_tool_failure(error, "add", ["sum"])
    end

    it "raises when retry is exhausted" do
      run = restricted_recovery_run(invalid_tool_recovery_prompt, disallowed_turn, 0)
      error = expect_raises(Crig::Completion::PromptError) do
        run.resolve_invalid_tool_call(Crig::InvalidToolCallHookAction.retry("choose an allowed tool"))
      end
      Conformance.validate_unknown_tool_failure(error, "add", ["sum"])
    end

    it "rejects a repair to a tool that is still disallowed" do
      run = restricted_recovery_run(invalid_tool_recovery_prompt, disallowed_turn, 0)
      error = expect_raises(Crig::Completion::PromptError) do
        run.resolve_invalid_tool_call(Crig::InvalidToolCallHookAction.repair("missing"))
      end
      Conformance.validate_unknown_tool_failure(error, "missing", ["sum"])
    end

    it "repairs to an allowed tool and produces a pending execution" do
      run = restricted_recovery_run(invalid_tool_recovery_prompt, disallowed_turn, 0)
      outcome = run.resolve_invalid_tool_call(Crig::InvalidToolCallHookAction.repair("sum"))
      outcome.kind.continue?.should be_true

      step = run.next_step
      step.kind.call_tools?.should be_true
      calls = step.calls || raise "no calls"
      calls.size.should eq(1)
      calls.first.tool_call.function.name.should eq("sum")
      calls.first.preresolved_result.should be_nil
    end

    it "skips the disallowed call with a pre-resolved result" do
      run = restricted_recovery_run(invalid_tool_recovery_prompt, disallowed_turn, 0)
      outcome = run.resolve_invalid_tool_call(Crig::InvalidToolCallHookAction.skip("disabled for this turn"))
      outcome.kind.continue?.should be_true

      step = run.next_step
      step.kind.call_tools?.should be_true
      calls = step.calls || raise "no calls"
      calls.size.should eq(1)
      calls.first.tool_call.function.name.should eq("add")
      calls.first.preresolved_result.should_not be_nil
    end
  end
end
