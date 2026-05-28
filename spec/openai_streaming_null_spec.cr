require "./spec_helper"

describe "OpenAI Streaming null_or_default" do
  it "deserializes tool call with null function as default Function" do
    json = %({"index":0,"id":"call_abc123","function":null})
    tool_call = Crig::Providers::OpenAI::Chat::Streaming::ToolCall.from_json(json)

    tool_call.index.should eq(0)
    tool_call.id.should eq("call_abc123")
    tool_call.function.name.should be_nil
    tool_call.function.arguments.should be_nil
  end

  it "deserializes tool call with missing function as default Function" do
    json = %({"index":0,"id":"call_abc123"})
    tool_call = Crig::Providers::OpenAI::Chat::Streaming::ToolCall.from_json(json)

    tool_call.index.should eq(0)
    tool_call.id.should eq("call_abc123")
    tool_call.function.name.should be_nil
    tool_call.function.arguments.should be_nil
  end
end
