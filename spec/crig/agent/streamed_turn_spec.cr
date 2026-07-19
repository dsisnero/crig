require "../../spec_helper"

describe "StreamedTurnAssembler" do
  it "accumulates text and emits ingested events" do
    s = Set(String).new
    t1 = Crig::StreamedTurnAssembler.new(s, s)
    t1.ingest(Crig::StreamedAssistantContent(Crig::FinalResponse).text("hel")).size.should eq(1)
  end

  it "text accumulates across calls" do
    s = Set(String).new
    t1 = Crig::StreamedTurnAssembler.new(s, s)
    t1.ingest(Crig::StreamedAssistantContent(Crig::FinalResponse).text("hel"))
    t1.ingest(Crig::StreamedAssistantContent(Crig::FinalResponse).text("lo"))
    t1.aggregated_text.should eq("hello")
  end

  it "ingest handles reasoning items" do
    s = Set(String).new
    t1 = Crig::StreamedTurnAssembler.new(s, s)
    r = Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.summary("think")], "r1")
    t1.ingest(Crig::StreamedAssistantContent(Crig::FinalResponse).reasoning(r)).size.should eq(1)
  end

  it "returns InvalidToolCall for disallowed tool" do
    allowed = ["add"]
    t1 = Crig::StreamedTurnAssembler.new(allowed.to_set, allowed.to_set)
    fn = Crig::Completion::ToolFunction.new("subtract", JSON.parse(%({"x":1})))
    tc = Crig::Completion::ToolCall.new("call_1", fn)
    events = t1.ingest(Crig::StreamedAssistantContent(Crig::FinalResponse).tool_call(tc, "internal_1"))
    events.size.should eq(1)
    events.first.kind.should eq(Crig::StreamedTurnEventKind::InvalidToolCall)
  end

  it "finish passes raw choice through for plain text" do
    s = Set(String).new
    t1 = Crig::StreamedTurnAssembler.new(s, s)
    t1.ingest(Crig::StreamedAssistantContent(Crig::FinalResponse).text("hi"))
    final_choice = Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("hi"))
    turn = t1.finish(nil, final_choice)
    turn.choice.size.should eq(1)
  end

  it "finish orders reasoning then text then tool calls" do
    allowed = ["add"]
    t1 = Crig::StreamedTurnAssembler.new(allowed.to_set, allowed.to_set)
    r = Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.summary("think")], "r1")
    t1.ingest(Crig::StreamedAssistantContent(Crig::FinalResponse).reasoning(r))
    fn = Crig::Completion::ToolFunction.new("add", JSON.parse(%({"x":1})))
    tc = Crig::Completion::ToolCall.new("call_1", fn)
    t1.ingest(Crig::StreamedAssistantContent(Crig::FinalResponse).tool_call(tc, "internal_1"))
    t1.ingest(Crig::StreamedAssistantContent(Crig::FinalResponse).text("answer"))

    final_choice = Crig::OneOrMany(Crig::Completion::AssistantContent).many([
      Crig::Completion::AssistantContent.text("answer"),
      Crig::Completion::AssistantContent.tool_call("call_1", "add", JSON.parse(%({"x":1}))),
    ]) || raise "need two items"

    turn = t1.finish("msg_1", final_choice)
    turn.choice.size.should eq(3)
    turn.message_id.should eq("msg_1")
  end
end
