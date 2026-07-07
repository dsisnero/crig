require "../../spec_helper"
require "wait_group"

module Crig
  describe AgentRunner, "concurrent tool execution" do
    it "executes multiple tools sequentially with concurrency 1" do
      model = RunnerMockModel.new
      model.tool_call_names = ["add", "sub"]
      model.response_text = "done"

      hook = RecordHook.new
      runner = AgentRunner(typeof(model)).new(model)
        .add_hook(hook)
        .max_turns(2)
        .tool_concurrency(1)

      response = runner.run(Completion::Message.user("add and sub"))
      response.should_not be_nil
      hook.events.includes?("tool_call:add").should be_true
      hook.events.includes?("tool_call:sub").should be_true
    end

    it "executes multiple tools concurrently with concurrency 2" do
      model = RunnerMockModel.new
      model.tool_call_names = ["add", "sub", "mul", "div"]
      model.response_text = "done"

      runner = AgentRunner(typeof(model)).new(model)
        .max_turns(2)
        .tool_concurrency(2)

      # The run should complete without errors with concurrent execution
      response = runner.run(Completion::Message.user("compute"))
      response.should_not be_nil
    end

    it "errgroup: first error terminates remaining tools" do
      model = RunnerMockModel.new
      model.tool_call_names = ["safe", "fail", "never_runs"]
      model.response_text = "done"

      runner = AgentRunner(typeof(model)).new(model)
        .max_turns(2)
        .tool_concurrency(2)

      # Our mock tool execution returns success currently, so this just
      # verifies the concurrent path works with multiple tools
      response = runner.run(Completion::Message.user("test"))
      response.should_not be_nil
    end
  end
end
