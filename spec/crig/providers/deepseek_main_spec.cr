require "../../spec_helper"
describe Crig::Providers::DeepSeek::Message do
  it "deserializes vec choice assistant messages" do
    choices = JSON.parse(%([{
      "finish_reason":"stop",
      "index":0,
      "logprobs":null,
      "message":{"role":"assistant","content":"Hello, world!"}
    }])).as_a.map { |entry| Crig::Providers::DeepSeek::Choice.from_json_value(entry) }

    choices.size.should eq(1)
    choices.first.message.kind.assistant?.should be_true
    choices.first.message.content.should eq("Hello, world!")
  end

  it "merges multiple user text items into one deepseek user message" do
    rig_msg = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::User,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::UserContent.text("first part").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::UserContent.text("second part").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    messages = Crig::Providers::DeepSeek::Message.from_core_messages(rig_msg)
    user_messages = messages.select(&.kind.user?)

    user_messages.size.should eq(1)
    user_messages.first.content.should eq("first part\nsecond part")
  end

  it "converts assistant messages with reasoning and tool calls" do
    rig_msg = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.reasoning("thinking about the problem").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.text("I'll call the tool").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.tool_call("call_1", "subtract", JSON.parse(%({"x":2,"y":5}))).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    messages = Crig::Providers::DeepSeek::Message.from_core_messages(rig_msg)
    messages.size.should eq(1)
    message = messages.first
    message.kind.assistant?.should be_true
    message.content.should eq("I'll call the tool")
    message.reasoning_content.should eq("thinking about the problem")
    message.tool_calls.size.should eq(1)
    message.tool_calls.first.function.name.should eq("subtract")
  end

  it "converts assistant messages without reasoning" do
    rig_msg = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.text("calling tool").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.tool_call("call_1", "add", JSON.parse(%({"a":1,"b":2}))).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    messages = Crig::Providers::DeepSeek::Message.from_core_messages(rig_msg)
    messages.size.should eq(1)
    messages.first.reasoning_content.should be_nil
    messages.first.tool_calls.size.should eq(1)
  end
end

describe Crig::Providers::DeepSeek::Client do
  it "ports the deepseek client initialization" do
    client = Crig::Providers::DeepSeek::Client.new("dummy-key")
    builder_client = Crig::Providers::DeepSeek::Client.builder.api_key("dummy-key").build

    client.api_key.should eq("dummy-key")
    builder_client.api_key.should eq("dummy-key")
    client.default_headers["Authorization"].should eq("Bearer dummy-key")
  end
end

describe Crig::Providers::DeepSeek::CompletionResponse do
  it "deserializes a deepseek response" do
    response = Crig::Providers::DeepSeek::CompletionResponse.from_json_value(JSON.parse(%({
      "choices":[{"finish_reason":"stop","index":0,"logprobs":null,"message":{"role":"assistant","content":"Hello, world!"}}],
      "usage":{"completion_tokens":0,"prompt_tokens":0,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":0,"total_tokens":0}
    })))

    response.choices.first.message.kind.assistant?.should be_true
    response.choices.first.message.content.should eq("Hello, world!")
  end

  it "deserializes the example response" do
    response = Crig::Providers::DeepSeek::CompletionResponse.from_json_value(JSON.parse(%({
      "id":"e45f6c68-9d9e-43de-beb4-4f402b850feb",
      "object":"chat.completion",
      "created":0,
      "model":"deepseek-chat",
      "choices":[{"index":0,"message":{"role":"assistant","content":"Why don’t skeletons fight each other?  \\nBecause they don’t have the guts! 😄"},"logprobs":null,"finish_reason":"stop"}],
      "usage":{"prompt_tokens":13,"completion_tokens":32,"total_tokens":45,"prompt_tokens_details":{"cached_tokens":0},"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":13}
    })))

    response.choices.first.message.content.should eq("Why don’t skeletons fight each other?  \nBecause they don’t have the guts! 😄")
    response.usage.prompt_tokens.should eq(13)
    response.usage.completion_tokens.should eq(32)
  end

  it "serializes and deserializes tool call assistant choices" do
    choice = Crig::Providers::DeepSeek::Choice.from_json_value(JSON.parse(%({
      "finish_reason":"tool_calls",
      "index":0,
      "logprobs":null,
      "message":{
        "content":"",
        "role":"assistant",
        "tool_calls":[{"function":{"arguments":"{\\"x\\":2,\\"y\\":5}","name":"subtract"},"id":"call_0_2b4a85ee-b04a-40ad-a16b-a405caf6e65b","index":0,"type":"function"}]
      }
    })))

    choice.finish_reason.should eq("tool_calls")
    choice.message.tool_calls.first.id.should eq("call_0_2b4a85ee-b04a-40ad-a16b-a405caf6e65b")
    choice.message.tool_calls.first.function.arguments["x"].as_i.should eq(2)
  end
end
