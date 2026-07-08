require "../../spec_helper"
require "../../support/runner_helpers"

module Crig
  describe AgentRunner, "tool roundtrip message chain" do
    it "produces correct message chain: user -> assistant(tool_call) -> user(tool_result)" do
      model = RunnerMockModel.new
      model.tool_call_name = "add"
      model.tool_call_args = %({"a":2,"b":3})
      model.response_text = "done"
      model.usage = Completion::Usage.new(input_tokens: 10, output_tokens: 5)

      runner = AgentRunner(typeof(model)).new(model).max_turns(2)

      # Run the agent loop step by step
      ctx = HookContext.new(is_streaming: false)
      run = AgentRun.new(Completion::Message.user("add 2 and 3")).max_turns(2)

      # Step 1: CallModel
      step1 = run.next_step
      raise "expected CallModel" unless step1.call_model?

      # Feed the model response (tool call)
      choice = OneOrMany(Completion::AssistantContent).one(
        Completion::AssistantContent.tool_call("call_xyz", "add", JSON.parse(%({"a":2,"b":3}))))
      outcome = run.model_response(ModelTurn.new(
        choice: choice,
        usage: Completion::Usage.new,
        allowed_tools: ["add"],
      ))
      raise "expected Continue" unless outcome.kind.continue?

      # Step 2: CallTools
      step2 = run.next_step
      raise "expected CallTools" unless step2.call_tools?
      calls = step2.calls.not_nil!
      calls.size.should eq(1)

      # Feed tool results
      tc = calls[0].tool_call
      content = OneOrMany(Completion::ToolResultContent).one(Completion::ToolResultContent.text("7"))
      result = Completion::UserContent.tool_result_with_call_id(tc.id, tc.id, content)
      run.tool_results([result])

      # Step 3: Next CallModel - check history
      step3 = run.next_step
      raise "expected CallModel" unless step3.call_model?

      history = step3.history.not_nil!
      # History should be [original_prompt, assistant(tool_call)]
      history.size.should eq(2)
      history[0].role.user?.should be_true      # original prompt
      history[1].role.assistant?.should be_true # assistant with tool_call

      # The tool call in the assistant message should have the correct id
      assistant_content = history[1].content.to_a
      ac = assistant_content.first
      ac.is_a?(Completion::AssistantContent).should be_true
      ac_tc = ac.as(Completion::AssistantContent).tool_call
      ac_tc.should_not be_nil
      ac_tc.not_nil!.id.should eq("call_xyz")

      # The prompt (next message) should be the tool result
      prompt = step3.prompt.not_nil!
      prompt.role.user?.should be_true
      tr_content = prompt.content.to_a.first
      tr_content.is_a?(Completion::UserContent).should be_true
      tr = tr_content.as(Completion::UserContent).tool_result
      tr.should_not be_nil
      tr.not_nil!.id.should eq("call_xyz")
    end
  end
end
