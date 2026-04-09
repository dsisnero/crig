require "../../../spec_helper"

describe Crig::Providers::XAI::Message do
  it "serializes redacted reasoning as encrypted content without leaking it into summary text" do
    reasoning = Crig::Completion::Reasoning.new(
      [
        Crig::Completion::ReasoningContent.text("explain"),
        Crig::Completion::ReasoningContent.redacted("opaque-redacted"),
      ],
      "rs_2"
    )
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(Crig::Completion::AssistantContent::Kind::Reasoning, reasoning: reasoning)
      ),
      "assistant_2"
    )

    items = Crig::Providers::XAI::Message.from_completion_message(message)
    items.size.should eq(1)
    item = items.first
    item.kind.should eq(Crig::Providers::XAI::Message::Kind::Reasoning)
    item.summary.not_nil!.map(&.text).should eq(["explain"])
    item.encrypted_content.should eq("opaque-redacted")
  end

  it "roundtrips empty reasoning content without error" do
    reasoning = Crig::Completion::Reasoning.new([] of Crig::Completion::ReasoningContent, "rs_empty")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(Crig::Completion::AssistantContent::Kind::Reasoning, reasoning: reasoning)
      ),
      "assistant_2b"
    )

    items = Crig::Providers::XAI::Message.from_completion_message(message)
    items.size.should eq(1)
    items.first.id.should eq("rs_empty")
    items.first.summary.not_nil!.should be_empty
    items.first.encrypted_content.should be_nil
  end

  it "returns an error when assistant reasoning has no id" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.reasoning("thinking")
      ),
      "assistant_no_reasoning_id"
    )

    expect_raises(Crig::Completion::CompletionError, /Assistant reasoning `id` is required/) do
      Crig::Providers::XAI::Message.from_completion_message(message)
    end
  end

  it "uses snake_case message type tags" do
    function_call = Crig::Providers::XAI::Message.function_call("call_1", "tool_name", %({"arg":1}))
    user_message = Crig::Providers::XAI::Message.user("hello")

    function_call.to_json_value["type"].as_s.should eq("function_call")
    user_message.to_json_value["type"].as_s.should eq("message")
  end

  it "returns an error when user tool results omit call_id" do
    message = Crig::Completion::Message.tool_result("tool_1", "result payload")

    expect_raises(Crig::Completion::CompletionError, /Tool result `call_id` is required/) do
      Crig::Providers::XAI::Message.from_completion_message(message)
    end
  end

  it "returns an error when assistant tool calls omit call_id" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.tool_call("tool_1", "my_tool", JSON.parse(%({"arg":"value"})))
      ),
      "assistant_3"
    )

    expect_raises(Crig::Completion::CompletionError, /Assistant tool call `call_id` is required/) do
      Crig::Providers::XAI::Message.from_completion_message(message)
    end
  end
end

describe Crig::Providers::XAI::ApiResponse do
  it "wraps success and error payloads with the typed helper" do
    ok = Crig::Providers::XAI::ApiResponse(String).from_json_value(JSON.parse(%({"value":"ok"}))) do |value|
      value["value"].as_s
    end
    err = Crig::Providers::XAI::ApiResponse(String).from_json_value(
      JSON.parse(%({"error":"bad request","code":"invalid_request"}))
    ) do |_value|
      raise "should not be called"
    end

    ok.ok.should eq("ok")
    ok.error.should be_nil
    err.ok.should be_nil
    err.error.not_nil!.message.should eq("Code `invalid_request`: bad request")
  end
end

describe Crig::Providers::XAI::ContentItem do
  it "serializes text, image, and file payloads" do
    text = Crig::Providers::XAI::ContentItem.text("hello").to_json_value
    image = Crig::Providers::XAI::ContentItem.image("https://example.com/cat.png", "high").to_json_value
    file = Crig::Providers::XAI::ContentItem.file(file_url: "https://example.com/doc.pdf").to_json_value

    text["type"].as_s.should eq("input_text")
    text["text"].as_s.should eq("hello")
    image["type"].as_s.should eq("input_image")
    image["image_url"].as_s.should eq("https://example.com/cat.png")
    image["detail"].as_s.should eq("high")
    file["type"].as_s.should eq("input_file")
    file["file_url"].as_s.should eq("https://example.com/doc.pdf")
  end
end

describe Crig::Providers::XAI::Content do
  it "serializes text and array multimodal content" do
    text = Crig::Providers::XAI::Content.text("hello").to_json_value
    array = Crig::Providers::XAI::Content.array([
      Crig::Providers::XAI::ContentItem.text("hello"),
      Crig::Providers::XAI::ContentItem.image("https://example.com/cat.png"),
    ]).to_json_value

    text.as_s.should eq("hello")
    array.as_a.map { |entry| entry["type"].as_s }.should eq(["input_text", "input_image"])
  end
end
