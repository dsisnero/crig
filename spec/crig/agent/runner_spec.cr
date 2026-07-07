require "../../spec_helper"

# Recording hook for verifying hook dispatch
class RecordHook
  include Crig::AgentHook

  getter events : Array(String) = [] of String

  def on_event(ctx : Crig::HookContext, event : Crig::StepEvent) : Crig::Flow
    case event.kind
    when .completion_call?     then @events << "completion_call"
    when .tool_call?           then @events << "tool_call:#{event.tool_name}"
    when .tool_result?         then @events << "tool_result:#{event.tool_name}"
    when .completion_response? then @events << "completion_response"
    else                            @events << "other:#{event.kind}"
    end
    Crig::Flow.cont
  end
end

# Simple completion model for testing AgentRunner
class RunnerMockModel
  include Crig::Completion::CompletionModel

  property response_text : String = "hello"
  property tool_call_name : String? = nil
  property tool_call_args : String = "{}"
  property usage : Crig::Completion::Usage = Crig::Completion::Usage.new(output_tokens: 1)
  property call_count : Int32 = 0

  def completion(request : Crig::Completion::Request::CompletionRequest) : Crig::Completion::CompletionResponse(String)
    @call_count += 1
    if name = @tool_call_name
      # Only return tool call on first call
      if @call_count == 1
        choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(
          Crig::Completion::AssistantContent.tool_call("call_1", name, JSON.parse(@tool_call_args)))
        return Crig::Completion::CompletionResponse(String).new(choice, @usage, "raw")
      end
    end
    choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(
      Crig::Completion::AssistantContent.text(@response_text))
    Crig::Completion::CompletionResponse(String).new(choice, @usage, "raw")
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    [Crig::StreamingCompletionResponse(String).new]
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    builder = Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
    if name = @tool_call_name
      builder = builder.tool(Crig::Completion::ToolDefinition.new(name, "test tool", JSON::Any.new({} of String => JSON::Any)))
    end
    builder
  end
end

# Simple tool server for testing
class RunnerMockToolServer
  def call_tool(name : String, args : String) : String
    "#{name}:#{args}"
  end
end

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
