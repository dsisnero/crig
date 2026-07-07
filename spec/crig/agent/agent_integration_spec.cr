require "../../spec_helper"
require "../../support/runner_helpers"

module Crig
  describe Agent, "v0.39.0 runner integration" do
    it "creates a runner from an agent" do
      model = RunnerMockModel.new
      agent = Agent(typeof(model)).new(model)

      runner = agent.runner(Completion::Message.user("hello"))
      runner.should be_a(AgentRunner(typeof(model)))
    end

    it "adds hooks to agent and they flow to runner" do
      model = RunnerMockModel.new
      model.response_text = "hi"
      hook = RecordHook.new

      agent = Agent(typeof(model)).new(model)
      agent = agent.add_hook(hook)

      runner = agent.runner(Completion::Message.user("hello"))
      response = runner.run(Completion::Message.user("hi"))

      response.should_not be_nil
      hook.events.should contain("completion_call")
    end

    it "runner respects agent preamble and temperature" do
      model = RunnerMockModel.new
      model.response_text = "hello"

      agent = Agent(typeof(model)).new(model, preamble: "Be helpful", temperature: 0.5)
      runner = agent.runner(Completion::Message.user("hi"))

      # Runner should run without errors
      response = runner.run(Completion::Message.user("hi"))
      response.output.should contain("hello")
    end
  end
end
