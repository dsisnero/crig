require "../../spec_helper"

private def expect_call_model(run : Crig::AgentRun) : Crig::AgentRunStep
  step = run.next_step
  raise "expected CallModel" unless step.call_model?
  step
end

private def expect_call_tools(run : Crig::AgentRun) : Array(Crig::PendingToolCall)
  step = run.next_step
  raise "expected CallTools" unless step.call_tools?
  step.calls.not_nil!
end

private def expect_continue(outcome : Crig::ModelTurnOutcome)
  raise "expected Continue" unless outcome.kind.continue?
end

private def tool_call_content(id : String, name : String, args : String = "{}") : Crig::Completion::AssistantContent
  Crig::Completion::AssistantContent.tool_call(id, name, JSON.parse(args))
end

module Crig
  describe AgentRun, "message ordering after tool roundtrip" do
    it "includes tool result in history for next model call" do
      run = AgentRun.new(Completion::Message.user("add 2 and 3")).max_turns(2)

      expect_call_model(run)

      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "add")),
        allowed_tools: ["add"],
      ))
      expect_continue(outcome)

      calls = expect_call_tools(run)
      tc = calls[0].tool_call
      result = Completion::UserContent.tool_result(tc.id,
        OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text("7")))
      run.tool_results([result])

      step2 = expect_call_model(run)
      history_after = step2.history.not_nil!
      prompt_after = step2.prompt.not_nil!

      history_after.size.should eq(2)
      history_after[0].role.user?.should be_true      # original prompt
      history_after[1].role.assistant?.should be_true # assistant

      prompt_after.role.user?.should be_true # tool result message
    end

    it "tool result message has correct tool_result content" do
      run = AgentRun.new(Completion::Message.user("add 2 and 3")).max_turns(2)
      expect_call_model(run)

      outcome = run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "add")),
        allowed_tools: ["add"],
      ))
      expect_continue(outcome)

      calls = expect_call_tools(run)
      tc = calls[0].tool_call
      result = Completion::UserContent.tool_result(tc.id,
        OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text("7")))
      run.tool_results([result])

      step2 = expect_call_model(run)
      prompt_after = step2.prompt.not_nil!

      prompt_after.role.user?.should be_true
      first_content = prompt_after.content.first.as(Completion::UserContent)
      first_content.kind.tool_result?.should be_true
    end
  end
end
