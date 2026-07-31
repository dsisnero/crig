require "../../spec_helper"
describe Crig::Providers::Perplexity::Message do
  it "deserializes and serializes typed perplexity messages" do
    message = Crig::Providers::Perplexity::Message.from_json_value(JSON.parse(%({
      "role":"user",
      "content":"Hello, how can I help you?"
    })))

    message.role.should eq(Crig::Providers::Perplexity::Role::User)
    message.content.should eq("Hello, how can I help you?")

    serialized = Crig::Providers::Perplexity::Message.new(
      Crig::Providers::Perplexity::Role::Assistant,
      "I am here to assist you."
    ).to_json_value
    serialized["role"].as_s.should eq("assistant")
    serialized["content"].as_s.should eq("I am here to assist you.")
  end

  it "round-trips between core text-only messages and perplexity messages" do
    user_message = Crig::Completion::Message.user("User message")
    assistant_message = Crig::Completion::Message.assistant("Assistant message")

    converted_user_message = Crig::Providers::Perplexity::Message.from_core_message(user_message)
    converted_assistant_message = Crig::Providers::Perplexity::Message.from_core_message(assistant_message)

    converted_user_message.role.should eq(Crig::Providers::Perplexity::Role::User)
    converted_user_message.content.should eq("User message")
    converted_assistant_message.role.should eq(Crig::Providers::Perplexity::Role::Assistant)
    converted_assistant_message.content.should eq("Assistant message")

    converted_user_message.to_core_message.should eq(user_message)
    converted_assistant_message.to_core_message.should eq(assistant_message)
  end
end

describe Crig::Providers::Perplexity::Client do
  it "supports rust-shaped client initialization" do
    client = Crig::Providers::Perplexity::Client.new("dummy-key")
    builder_client = Crig::Providers::Perplexity::Client.builder
      .api_key("dummy-key")
      .build

    client.api_key.token.should eq("dummy-key")
    builder_client.api_key.token.should eq("dummy-key")
  end

  it "posts perplexity chat completions requests and parses the returned response" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"pplx_1",
          "model":"sonar",
          "object":"chat.completion",
          "created":1,
          "choices":[{
            "index":0,
            "finish_reason":"stop",
            "message":{"role":"assistant","content":"perplexity answer"},
            "delta":{"role":"assistant","content":"perplexity answer"}
          }],
          "usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Perplexity::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Perplexity::SONAR)
      .completion(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    response.choice.first.text.not_nil!.text.should eq("perplexity answer")
    response.usage.total_tokens.should eq(3)
    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::Perplexity::SONAR)
    posted["messages"].as_a.first["role"].as_s.should eq("user")
    posted["stream"].as_bool.should be_false

    http_server.close
  end

  it "parses perplexity streaming text deltas" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "text/event-stream",
        body:         <<-SSE,
data: {"id":"pplx-stream","model":"sonar","choices":[{"index":0,"delta":{"role":"assistant","content":"hello "}}]}

data: {"id":"pplx-stream","model":"sonar","choices":[{"index":0,"delta":{"role":"assistant","content":"world"}}],"usage":{"prompt_tokens":2,"completion_tokens":2,"total_tokens":4}}

data: [DONE]

SSE
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Perplexity::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Perplexity::SONAR_PRO)
      .stream(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    items = [] of Crig::StreamedAssistantContent(Crig::Client::FinalCompletionResponse)
    response.each_item { |item| items << item }

    items.select(&.kind.text?).map { |item| item.text.not_nil!.text }.should eq(["hello ", "world"])
    items.last.kind.final?.should be_true
    response.message_id.should eq("pplx-stream")

    http_server.close
  end
end
