require "../../spec_helper"

module Crig
  describe AgentRun, "serialization" do
    it "serializes and deserializes fresh run preserving max_turns and turn" do
      run = AgentRun.new(Completion::Message.user("hello"))
      json = run.to_json
      restored = AgentRun.from_json(json)

      restored.max_turns.should eq(0)
      restored.turn.should eq(0)
    end

    it "serializes and deserializes mid-run preserving pending tool calls" do
      run = AgentRun.new(Completion::Message.user("add 2 and 3")).max_turns(2)
      expect_call_model(run)

      run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(
          tool_call_content("call_1", "add"),
        ),
        allowed_tools: ["add"],
      ))
      expect_continue_model(run)

      json = run.to_json
      restored = AgentRun.from_json(json)

      # Resumed run should re-emit the pending tool calls
      step = restored.next_step
      step.call_tools?.should be_true
      calls = step.calls.not_nil!
      calls.size.should eq(1)
      calls[0].tool_call.function.name.should eq("add")
    end

    it "resumed run completes after feeding tool results" do
      run = AgentRun.new(Completion::Message.user("add 2 and 3")).max_turns(2)
      expect_call_model(run)

      run.model_response(ModelTurn.new(
        choice: OneOrMany(Completion::AssistantContent).one(tool_call_content("call_1", "add")),
        allowed_tools: ["add"],
      ))
      expect_continue_model(run)

      json = run.to_json
      restored = AgentRun.from_json(json)
      step = restored.next_step
      tc = step.calls.not_nil![0].tool_call

      result = Completion::UserContent.tool_result(tc.id,
        OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text("7")))
      restored.tool_results([result])

      step3 = restored.next_step
      step3.call_model?.should be_true
    end
  end
end

private def expect_call_model(run)
  step = run.next_step
  raise "expected CallModel" unless step.call_model?
  step
end

private def expect_continue_model(run)
  step = run.next_step
  raise "expected CallTools" unless step.call_tools?
  step
end

private def tool_call_content(id : String, name : String, args : String = "{}") : Crig::Completion::AssistantContent
  Crig::Completion::AssistantContent.tool_call(id, name, JSON.parse(args))
end
