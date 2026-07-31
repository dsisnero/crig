require "../../spec_helper"
require "../../support/runner_helpers"

module Crig
  describe AgentRunner, "streaming" do
    it "streams text-only prompt to completion channel" do
      model = RunnerMockModel.new
      model.response_text = "Hi there!"
      runner = AgentRunner(typeof(model)).new(model)

      ch = runner.stream(Completion::Message.user("hello"))
      items = [] of DriveItem
      errors = [] of StreamError

      while item = ch.receive?
        case item
        when StreamError then errors << item
        else                  items << item.as(DriveItem)
        end
      end

      errors.should be_empty
      items.any? { |i| i.is_a?(StreamTextDelta) }.should be_true
      items.any? { |i| i.is_a?(StreamDone) }.should be_true
    end

    it "dispatches the text-delta observation hook during streaming" do
      model = RunnerMockModel.new
      model.response_text = "Hi there!"
      hook = TextDeltaHook.new
      runner = AgentRunner(typeof(model)).new(model).add_hook(hook)

      ch = runner.stream(Completion::Message.user("hello"))
      while item = ch.receive?
        # drain
      end

      hook.deltas.should_not be_empty
      hook.deltas.includes?("Hi there!").should be_true
    end

    it "streams tool roundtrip" do
      model = RunnerMockModel.new
      model.tool_call_name = "add"
      model.tool_call_args = %({"a":2})
      model.response_text = "result is 5"

      runner = AgentRunner(typeof(model)).new(model)
        .max_turns(2)

      ch = runner.stream(Completion::Message.user("add 2 and 3"))
      items = [] of DriveItem

      while item = ch.receive?
        if item.is_a?(StreamError)
          raise item.error
        else
          items << item.as(DriveItem)
        end
      end

      items.any? { |i| i.is_a?(StreamToolResult) }.should be_true
      items.any? { |i| i.is_a?(StreamDone) }.should be_true
    end

    it "streaming hook records events in order" do
      model = RunnerMockModel.new
      model.response_text = "hello"

      hook = RecordHook.new
      runner = AgentRunner(typeof(model)).new(model).add_hook(hook)

      ch = runner.stream(Completion::Message.user("hi"))
      while ch.receive?
        # drain
      end

      hook.events.should contain("completion_call")
    end
  end
end
