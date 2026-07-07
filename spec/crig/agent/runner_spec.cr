require "../../spec_helper"

module Crig
  describe AgentRunner do
    it "runs text-only prompt to completion" do
      model = RunnerMockModel.new
      model.response_text = "Hi there!"
      runner = AgentRunner(typeof(model)).new(model)

      response = runner.run(Completion::Message.user("hello"))
      response.output.should contain("Hi there")
    end

    it "dispatches completion_call hook" do
      model = RunnerMockModel.new
      hook = RecordHook.new
      runner = AgentRunner(typeof(model)).new(model).add_hook(hook)

      runner.run(Completion::Message.user("hi"))
      hook.events.should contain("completion_call")
    end

    it "runs tool roundtrip and dispatches hooks" do
      model = RunnerMockModel.new
      model.tool_call_name = "add"
      model.tool_call_args = %({"a": 2, "b": 3})
      model.response_text = "the answer is 5"

      hook = RecordHook.new
      runner = AgentRunner(typeof(model)).new(model)
        .add_hook(hook)
        .max_turns(2)

      response = runner.run(Completion::Message.user("add 2 and 3"))
      response.output.should_not be_empty
      hook.events.includes?("tool_call:add").should be_true
      hook.events.includes?("tool_result:add").should be_true
    end
  end
end
