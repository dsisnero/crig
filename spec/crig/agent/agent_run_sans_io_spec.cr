require "../../spec_helper"

module Crig
  describe AgentRun do
    it "starts in CallModel state with initial prompt" do
      prompt = Completion::Message.user("hello")
      run = AgentRun.new(prompt)
      step = run.next_step
      step.kind.call_model?.should be_true
    end

    it "accepts chat_history via with_history" do
      prompt = Completion::Message.user("hello")
      history = [Completion::Message.user("previous")]
      run = AgentRun.new(prompt).with_history(history)
      step = run.next_step
      step.history.should be_truthy
      step.history.try(&.size).should eq(1)
    end

    it "max_turns limits model calls" do
      prompt = Completion::Message.user("hello")
      run = AgentRun.new(prompt).max_turns(1)
      step = run.next_step
      step.kind.call_model?.should be_true
      # Feed a model response with no tool calls
      choice = OneOrMany(Completion::AssistantContent).one(
        Completion::AssistantContent.text("ok"))
      turn = ModelTurn.new(choice: choice, usage: Completion::Usage.new, allowed_tools: [] of String)
      outcome = run.model_response(turn)
      outcome.kind.continue?.should be_true
      step2 = run.next_step
      step2.kind.done?.should be_true
    end

    it "tool call in allowed list transitions to Continue" do
      prompt = Completion::Message.user("use tools")
      run = AgentRun.new(prompt)
      step = run.next_step
      step.kind.call_model?.should be_true
      tool_call = Completion::AssistantContent.tool_call("tc1", "echo", JSON.parse(%({"value":"hi"})))
      choice = OneOrMany(Completion::AssistantContent).one(tool_call)
      turn = ModelTurn.new(choice: choice, usage: Completion::Usage.new, allowed_tools: ["echo"])
      outcome = run.model_response(turn)
      outcome.kind.continue?.should be_true
    end

    it "sans-I/O: no model, tools, hooks, or memory required" do
      prompt = Completion::Message.user("hello")
      run = AgentRun.new(prompt)
      # Operates purely on messages and state — no external dependencies
      step = run.next_step
      step.kind.call_model?.should be_true
      # Feed text response
      choice = OneOrMany(Completion::AssistantContent).one(
        Completion::AssistantContent.text("ok"))
      turn = ModelTurn.new(choice: choice, usage: Completion::Usage.new, allowed_tools: [] of String)
      outcome = run.model_response(turn)
      outcome.kind.continue?.should be_true
      step2 = run.next_step
      step2.kind.done?.should be_true
      step2.response.should be_truthy
    end
  end
end
