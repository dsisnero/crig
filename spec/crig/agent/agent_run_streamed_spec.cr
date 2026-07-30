require "../../spec_helper"

def make_asm(allowed : Set(String))
  Crig::StreamedTurnAssembler.new(allowed, allowed)
end

def tool_call_item(id : String, name : String, args : String = %({"x":1}))
  fn = Crig::Completion::ToolFunction.new(name, JSON.parse(args))
  tc = Crig::Completion::ToolCall.new(id, fn)
  Crig::StreamedAssistantContent(Crig::PromptResponse).tool_call(tc, "internal_#{id}")
end

describe "AgentRun streamed turn support" do
  it "record_streamed_completion_call records usage during AwaitingModel" do
    run = Crig::AgentRun.new("hello").max_turns(2)
    run.next_step
    usage = Crig::Completion::Usage.new(input_tokens: 5, output_tokens: 7, total_tokens: 12)
    run.record_streamed_completion_call(usage)
    run.completion_calls.size.should eq(1)
    run.completion_calls[0].usage.should eq(usage)
  end

  it "record_streamed_completion_call rejects duplicate calls" do
    run = Crig::AgentRun.new("hello").max_turns(2)
    run.next_step
    run.record_streamed_completion_call(Crig::Completion::Usage.new)
    expect_raises(Crig::Completion::PromptError) do
      run.record_streamed_completion_call(Crig::Completion::Usage.new)
    end
  end

  it "streamed_turn completes a tool roundtrip" do
    allowed = Set{"add"}
    t1 = make_asm(allowed)
    t1.ingest(tool_call_item("tc_1", "add"))

    run = Crig::AgentRun.new("add things").max_turns(2)
    run.next_step
    run.record_streamed_completion_call(Crig::Completion::Usage.new)
    final_choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(
      Crig::Completion::AssistantContent.tool_call("tc_1", "add", JSON.parse(%({"x":1}))))
    turn = t1.finish("msg_1", final_choice)
    run.streamed_turn(turn)

    step = run.next_step
    step.call_tools?.should be_true
    calls = step.calls.not_nil!
    calls.size.should eq(1)
  end

  it "streamed_turn auto-records completion call when driver did not" do
    allowed = [] of String
    t1 = make_asm(allowed.to_set)
    run = Crig::AgentRun.new("hello").max_turns(2)
    run.next_step

    final_choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("done"))
    turn = t1.finish(nil, final_choice)
    run.streamed_turn(turn)

    run.completion_calls.size.should eq(1)
  end

  it "streamed_turn rejects unknown tool calls fail-fast" do
    allowed = Set{"add"}
    run = Crig::AgentRun.new("use tool").max_turns(2)
    run.next_step

    turn = Crig::StreamedTurn.new(
      message_id: nil,
      choice: Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.tool_call("tc_1", "unknown", JSON.parse(%({"x":1})))),
      executable_tool_names: allowed,
      allowed_tool_names: allowed,
    )
    expect_raises(Crig::Completion::PromptError) do
      run.streamed_turn(turn)
    end
  end
end
