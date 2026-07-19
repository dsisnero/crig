require "../../spec_helper"

module Crig
  describe AgentRun do
    it "serialization round-trip preserves max_turns" do
      run = AgentRun.new("hello").max_turns(5)
      json = run.to_json
      restored = AgentRun.from_json(json)
      restored.max_turns.should eq(5)
    end

    it "serialization round-trip preserves chat_history" do
      run = AgentRun.new("hello")
      json = run.to_json
      restored = AgentRun.from_json(json)
      restored.full_history.size.should eq(1)
    end

    it "serializes completion_calls" do
      run = AgentRun.new("test")
      run.completion_calls = [CompletionCall.new(0, Completion::Usage.new)]
      json = run.to_json
      restored = AgentRun.from_json(json)
      restored.completion_calls.size.should eq(1)
    end

    it "AgentRun.from_json creates runnable instance" do
      run = AgentRun.new("hello").max_turns(3)
      json = run.to_json
      restored = AgentRun.from_json(json)
      step = restored.next_step
      step.call_model?.should be_true
    end
  end
end
