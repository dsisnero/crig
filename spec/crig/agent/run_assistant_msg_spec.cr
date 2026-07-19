require "../../spec_helper"

module Crig
  describe AgentRun, "assistant_msg includes all choice items" do
    it "creates assistant message with all content items, not just first" do
      run = AgentRun.new(Completion::Message.user("hi")).max_turns(2)
      step = run.next_step

      # Model returns reasoning + tool_call
      items = [
        Completion::AssistantContent.reasoning("Let me think..."),
        Completion::AssistantContent.tool_call("call_1", "add", JSON.parse(%({"a":1}))),
      ]
      choice = OneOrMany(Completion::AssistantContent).many(items)

      outcome = run.model_response(ModelTurn.new(
        choice: choice,
        allowed_tools: ["add"],
      ))
      expect_continue(outcome)

      # Verify assistant message has both items
      msgs = run.messages
      msgs.size.should eq(2) # prompt + assistant
      assistant_msg = msgs[1]
      assistant_msg.role.assistant?.should be_true
      contents = assistant_msg.content.to_a
      contents.size.should eq(2)
      contents[0].as(Completion::AssistantContent).reasoning.should_not be_nil
      contents[1].as(Completion::AssistantContent).tool_call.should_not be_nil
    end
  end
end

private def expect_call_model(run)
  step = run.next_step
  raise "expected CallModel" unless step.call_model?
  step
end

private def expect_continue(outcome)
  raise "expected Continue" unless outcome.kind.continue?
end
