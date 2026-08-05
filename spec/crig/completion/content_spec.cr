require "../../spec_helper"
describe Crig::Completion::MimeType do
  it "round-trips known media types" do
    image = Crig::Completion::MimeType.from_mime_type("image/png")
    document = Crig::Completion::MimeType.from_mime_type("text/plain")
    audio = Crig::Completion::MimeType.from_mime_type("audio/mp3")
    video = Crig::Completion::MimeType.from_mime_type("video/webm")

    image.should_not be_nil
    document.should_not be_nil
    audio.should_not be_nil
    video.should_not be_nil

    Crig::Completion::MimeType.to_mime_type(image.as(Crig::Completion::MediaType)).should eq("image/png")
    Crig::Completion::MimeType.to_mime_type(document.as(Crig::Completion::MediaType)).should eq("text/plain")
    Crig::Completion::MimeType.to_mime_type(audio.as(Crig::Completion::MediaType)).should eq("audio/mp3")
    Crig::Completion::MimeType.to_mime_type(video.as(Crig::Completion::MediaType)).should eq("video/webm")
  end
end

describe Crig::Completion::DocumentSourceKind do
  it "round-trips json variants" do
    variants = [
      Crig::Completion::DocumentSourceKind.url("https://example.com/file"),
      Crig::Completion::DocumentSourceKind.base64("Zm9v"),
      Crig::Completion::DocumentSourceKind.raw(Bytes[1_u8, 2_u8, 3_u8]),
      Crig::Completion::DocumentSourceKind.string("hello"),
      Crig::Completion::DocumentSourceKind.unknown,
    ]

    variants.each do |variant|
      roundtrip = Crig::Completion::DocumentSourceKind.from_json(variant.to_json)

      roundtrip.kind.should eq(variant.kind)
      roundtrip.string_value.should eq(variant.string_value)
      roundtrip.bytes_value.should eq(variant.bytes_value)
    end
  end
end

describe Crig::Completion::Reasoning do
  it "tracks reasoning constructors and accessors" do
    reasoning = Crig::Completion::Reasoning.new_with_signature("hello", "sig")
      .with_id("reason-1")

    reasoning.first_text.should eq("hello")
    reasoning.first_signature.should eq("sig")
    reasoning.id.should eq("reason-1")
    reasoning.display_text.should eq("hello")
  end

  it "tracks encrypted and summary content" do
    encrypted = Crig::Completion::Reasoning.encrypted("secret")
    encrypted.encrypted_content.should eq("secret")

    summary = Crig::Completion::Reasoning.summaries(["one", "two"])
    summary.display_text.should eq("one\ntwo")
  end
end

describe Crig::Completion::ReasoningContent, tags: %w[completion content] do
  it "round-trips json variants" do
    variants = [
      Crig::Completion::ReasoningContent.text("plain", "sig"),
      Crig::Completion::ReasoningContent.encrypted("opaque"),
      Crig::Completion::ReasoningContent.redacted("redacted"),
      Crig::Completion::ReasoningContent.summary("summary"),
    ]

    variants.each do |variant|
      roundtrip = Crig::Completion::ReasoningContent.from_json(variant.to_json)

      roundtrip.kind.should eq(variant.kind)
      roundtrip.text.should eq(variant.text)
      roundtrip.signature.should eq(variant.signature)
      roundtrip.data.should eq(variant.data)
      roundtrip.summary.should eq(variant.summary)
    end
  end
end

describe Crig::Completion::ToolResultContent, tags: %w[completion content] do
  it "parses text tool output" do
    content = Crig::Completion::ToolResultContent.from_tool_output("plain text")
    text = content.first.text
    text.should_not be_nil

    content.first.kind.text?.should be_true
    text.as(Crig::Completion::Text).text.should eq("plain text")
  end

  it "parses image tool output" do
    content = Crig::Completion::ToolResultContent.from_tool_output(%({"type":"image","data":"https://example.com/image.png","mimeType":"image/png"}))
    image = content.first.image
    image.should_not be_nil

    content.first.kind.image?.should be_true
    image.as(Crig::Completion::Image).try_into_url.should eq("https://example.com/image.png")
  end

  it "builds raw image content helpers" do
    content = Crig::Completion::ToolResultContent.image_raw(Bytes[1_u8, 2_u8], Crig::Completion::ImageMediaType::PNG)
    image = content.image

    content.kind.image?.should be_true
    image.should_not be_nil
    image.as(Crig::Completion::Image).data.kind.raw?.should be_true
  end
end

describe Crig::Completion::Usage, tags: %w[completion usage] do
  it "accumulates usage totals" do
    a = Crig::Completion::Usage.new(
      input_tokens: 1,
      output_tokens: 2,
      total_tokens: 3,
      cached_input_tokens: 4,
    )
    b = Crig::Completion::Usage.new(
      input_tokens: 10,
      output_tokens: 20,
      total_tokens: 30,
      cached_input_tokens: 40,
    )

    (a + b).should eq(
      Crig::Completion::Usage.new(
        input_tokens: 11,
        output_tokens: 22,
        total_tokens: 33,
        cached_input_tokens: 44,
      )
    )
  end

  it "supports in-place accumulation" do
    usage = Crig::Completion::Usage.new(input_tokens: 1, output_tokens: 2, total_tokens: 3, cached_input_tokens: 4)
    usage.add!(Crig::Completion::Usage.new(input_tokens: 10, output_tokens: 20, total_tokens: 30, cached_input_tokens: 40))

    usage.should eq(
      Crig::Completion::Usage.new(
        input_tokens: 11,
        output_tokens: 22,
        total_tokens: 33,
        cached_input_tokens: 44,
      )
    )
  end

  it "reports whether any usage values are set" do
    Crig::Completion::Usage.new.has_values?.should be_false
    Crig::Completion::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 0).has_values?.should be_false
    Crig::Completion::Usage.new(input_tokens: 1).has_values?.should be_true
    Crig::Completion::Usage.new(output_tokens: 5).has_values?.should be_true
    Crig::Completion::Usage.new(total_tokens: 3).has_values?.should be_true
    Crig::Completion::Usage.new(cached_input_tokens: 2).has_values?.should be_true
  end
end

describe Crig::Completion::CompletionResponse do
  it "stores assistant content, usage, and raw response" do
    response = Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("hello")),
      Crig::Completion::Usage.new(input_tokens: 1, output_tokens: 2, total_tokens: 3),
      "raw",
      "msg-1",
    )

    response.choice.first.kind.text?.should be_true
    response.usage.total_tokens.should eq(3)
    response.raw_response.should eq("raw")
    response.message_id.should eq("msg-1")
  end
end

describe Crig::Completion::ToolDefinition, tags: %w[completion tool] do
  it "round-trips via JSON::Serializable" do
    definition = Crig::Completion::ToolDefinition.new(
      "weather",
      "Fetch weather",
      JSON.parse(%({"type":"object"}))
    )

    parsed = Crig::Completion::ToolDefinition.from_json(definition.to_json)

    parsed.name.should eq("weather")
    parsed.description.should eq("Fetch weather")
    parsed.parameters["type"].as_s.should eq("object")
  end
end
