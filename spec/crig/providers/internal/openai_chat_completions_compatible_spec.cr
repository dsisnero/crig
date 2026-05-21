require "../../../spec_helper"

describe "OpenAICompatible tool call finalization" do
  mod = Crig::Providers::Internal::OpenAICompatible

  it "preserves parameterless tool calls (null arguments → {})" do
    tool_call = Crig::RawStreamingToolCall.new("call_123", "ping", JSON::Any.new(nil))

    finalized = mod.finalize_pending_tool_call(tool_call)
    finalized.should_not be_nil
    finalized.not_nil!.id.should eq("call_123")
    finalized.not_nil!.name.should eq("ping")
    finalized.not_nil!.arguments.should eq(JSON.parse("{}"))
  end

  it "preserves empty argument chunks as empty object" do
    tool_call = Crig::RawStreamingToolCall.new("call_123", "ping", JSON::Any.new(""))

    finalized = mod.finalize_pending_tool_call(tool_call)
    finalized.should_not be_nil
    finalized.not_nil!.arguments.should eq(JSON.parse("{}"))
  end

  it "drops nameless pending entries" do
    tool_call = Crig::RawStreamingToolCall.empty

    mod.finalize_pending_tool_call(tool_call).should be_nil
  end

  it "drops partial argument payloads" do
    tool_call = Crig::RawStreamingToolCall.new("call_123", "ping", JSON::Any.new(%({"x":)))

    mod.finalize_pending_tool_call(tool_call).should be_nil
  end

  it "replaces null placeholder with following json fragments" do
    tool_call = Crig::RawStreamingToolCall.new("call_123", "web_search", JSON::Any.new("null"))

    tool_call = mod.append_tool_call_arguments(tool_call, %({"query": "META))
    tool_call = mod.append_tool_call_arguments(tool_call, %( Platforms news"}))

    tool_call.arguments.should eq(JSON.parse(%({"query": "META Platforms news"})))
  end
end

describe "OpenAICompatible should_evict_distinct_named_tool_call" do
  mod = Crig::Providers::Internal::OpenAICompatible

  it "returns false when incoming has no id" do
    existing = Crig::RawStreamingToolCall.new("call_aaa", "search", JSON::Any.new("{}"))
    incoming = Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk.new(
      index: 0, id: nil, name: "search", arguments: "{}",
    )

    mod.should_evict_distinct_named_tool_call(existing, incoming).should be_false
  end

  it "returns false when ids match" do
    existing = Crig::RawStreamingToolCall.new("call_aaa", "search", JSON::Any.new("{}"))
    incoming = Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk.new(
      index: 0, id: "call_aaa", name: "git", arguments: "",
    )

    mod.should_evict_distinct_named_tool_call(existing, incoming).should be_false
  end

  it "evicts distinct-name tool calls at the same index" do
    existing = Crig::RawStreamingToolCall.new("call_aaa", "search", JSON::Any.new("{}"))
    incoming = Crig::Providers::Internal::OpenAICompatible::CompatibleToolCallChunk.new(
      index: 0, id: "call_bbb", name: "git", arguments: "",
    )

    mod.should_evict_distinct_named_tool_call(existing, incoming).should be_true
  end
end
