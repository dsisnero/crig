require "../../spec_helper"
describe Crig::Completion::PromptError do
  it "builds a cancelled prompt error with context" do
    history = [Crig::Completion::Message.user("hello")]
    error = Crig::Completion::PromptError.prompt_cancelled(history, "stop")

    error.message.should eq("PromptCancelled: stop")
    error.kind.should eq(Crig::Completion::PromptError::Kind::PromptCancelled)
    error.reason.should eq("stop")
    error.chat_history.should eq(history)
  end

  it "builds a max turns exceeded error with context" do
    history = [Crig::Completion::Message.user("hello")]
    prompt = Crig::Completion::Message.user("tool again")
    error = Crig::Completion::PromptError.max_turns_exceeded(0, history, prompt)

    error.message.should eq("MaxTurnsExceeded: 0")
    error.kind.should eq(Crig::Completion::PromptError::Kind::MaxTurnsError)
    error.reason.should eq("MaxTurnsExceeded: 0")
    error.chat_history.should eq(history)
    error.prompt.should eq(prompt)
    error.max_turns.should eq(0)
  end

  it "wraps completion, tool, and tool-server errors" do
    completion = Crig::Completion::PromptError.completion_error(
      Crig::Completion::CompletionError.provider_error("provider down")
    )
    tool = Crig::Completion::PromptError.tool_error(
      Crig::ToolSetError.tool_not_found("lookup")
    )
    tool_server = Crig::Completion::PromptError.tool_server_error(
      Crig::ToolServerError.send_error("disconnected")
    )

    completion.kind.should eq(Crig::Completion::PromptError::Kind::CompletionError)
    completion.completion_error.not_nil!.message.should eq("ProviderError: provider down")
    tool.kind.should eq(Crig::Completion::PromptError::Kind::ToolError)
    tool.tool_error.not_nil!.message.should eq("ToolNotFoundError: lookup")
    tool_server.kind.should eq(Crig::Completion::PromptError::Kind::ToolServerError)
    tool_server.tool_server_error.not_nil!.message.should eq("SendError: disconnected")
  end
end

describe Crig::Completion::Request::Document, tags: %w[completion request] do
  it "renders without metadata" do
    document = Crig::Completion::Request::Document.new("123", "This is a test document.")

    document.to_s.should eq("<file id: 123>\nThis is a test document.\n</file>\n")
  end

  it "renders with sorted metadata" do
    document = Crig::Completion::Request::Document.new(
      "123",
      "This is a test document.",
      {"length" => "42", "author" => "John Doe"}
    )

    document.to_s.should eq("<file id: 123>\n<metadata author: \"John Doe\" length: \"42\" />\nThis is a test document.\n</file>\n")
  end
end

describe Crig::Completion::Request::CompletionRequest, tags: %w[completion request] do
  it "normalizes documents into a user message" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("What is the capital of France?")),
      documents: [
        Crig::Completion::Request::Document.new("doc1", "Document 1 text."),
        Crig::Completion::Request::Document.new("doc2", "Document 2 text."),
      ]
    )

    normalized = request.normalized_documents
    normalized.should_not be_nil
    message = normalized.as(Crig::Completion::Message)
    message.role.user?.should be_true
    message.content.to_a.size.should eq(2)
  end

  it "returns nil when there are no documents" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("hello"))
    )

    request.normalized_documents.should be_nil
  end

  it "derives the output schema name from title" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("hello")),
      output_schema: JSON.parse(%({"title":"weather_response"}))
    )

    request.output_schema_name.should eq("weather_response")
  end
end

describe Crig::Completion::Request::CompletionRequestBuilder, tags: %w[completion builder] do
  it "builds a completion request from prompt, history, and documents" do
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Who are you?")
      .preamble("You are Marvin.")
      .message(Crig::Completion::Message.user("Earlier"))
      .document(Crig::Completion::Request::Document.new("doc1", "Document 1 text."))
      .tool_choice(Crig::Completion::ToolChoice.required)
      .max_tokens(42)
      .build

    request.preamble.should eq("You are Marvin.")
    request.chat_history.to_a.size.should eq(2)
    request.documents.size.should eq(1)
    request.tool_choice.try(&.kind.required?).should be_true
    request.max_tokens.should eq(42)
  end

  it "sends through a completion model" do
    model = FakeCompletionModel.new
    response = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Who are you?")
      .send(model)

    response.raw_response.should eq("raw")
    model.last_request.should_not be_nil
  end

  it "merges additional params objects" do
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Who are you?")
      .additional_params(JSON.parse(%({"outer":{"a":1}})))
      .additional_params(JSON.parse(%({"outer":{"b":2},"other":3})))
      .build

    request.additional_params.should_not be_nil
    params = request.additional_params.as(JSON::Any)
    params["outer"]["a"].as_i.should eq(1)
    params["outer"]["b"].as_i.should eq(2)
    params["other"].as_i.should eq(3)
  end

  it "builds from string prompts via from_prompt" do
    builder = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Who are you?")

    builder.prompt.rag_text.should eq("Who are you?")
  end

  it "builds from string prompts via new" do
    builder = Crig::Completion::Request::CompletionRequestBuilder.new("Who are you?")

    builder.prompt.rag_text.should eq("Who are you?")
  end

  it "builds from message prompts via new" do
    prompt = Crig::Completion::Message.user("Who are you?")
    builder = Crig::Completion::Request::CompletionRequestBuilder.new(prompt)

    builder.prompt.should eq(prompt)
  end
end

describe Crig::Completion::ToolChoice, tags: %w[completion tool_choice] do
  it "supports specific function selection" do
    choice = Crig::Completion::ToolChoice.specific(["weather", "stocks"])

    choice.kind.specific?.should be_true
    choice.function_names.should eq(["weather", "stocks"])
  end

  it "round-trips json variants" do
    variants = [
      Crig::Completion::ToolChoice.auto,
      Crig::Completion::ToolChoice.none,
      Crig::Completion::ToolChoice.required,
      Crig::Completion::ToolChoice.specific(["weather"]),
    ]

    variants.each do |variant|
      roundtrip = Crig::Completion::ToolChoice.from_json(variant.to_json)

      roundtrip.kind.should eq(variant.kind)
      roundtrip.function_names.should eq(variant.function_names)
    end
  end
end

describe Crig::Completion::MediaType do
  it "round-trips json variants" do
    variants = [
      Crig::Completion::MediaType.image(Crig::Completion::ImageMediaType::PNG),
      Crig::Completion::MediaType.audio(Crig::Completion::AudioMediaType::MP3),
      Crig::Completion::MediaType.document(Crig::Completion::DocumentMediaType::TXT),
      Crig::Completion::MediaType.video(Crig::Completion::VideoMediaType::WEBM),
    ]

    variants.each do |variant|
      roundtrip = Crig::Completion::MediaType.from_json(variant.to_json)

      roundtrip.kind.should eq(variant.kind)
      roundtrip.image.should eq(variant.image)
      roundtrip.audio.should eq(variant.audio)
      roundtrip.document.should eq(variant.document)
      roundtrip.video.should eq(variant.video)
    end
  end
end

describe Crig::Completion::ImageDetail do
  it "parses upstream detail variants" do
    Crig::Completion::ImageDetail.parse?("low").should eq(Crig::Completion::ImageDetail::Low)
    Crig::Completion::ImageDetail.parse?("high").should eq(Crig::Completion::ImageDetail::High)
    Crig::Completion::ImageDetail.parse?("auto").should eq(Crig::Completion::ImageDetail::Auto)
    Crig::Completion::ImageDetail.parse?("unknown").should be_nil
  end
end

describe Crig::Completion::Image do
  it "builds wrapper helpers for common source kinds" do
    params = JSON.parse(%({"provider":"test"}))
    url = Crig::Completion::Image.url("https://example.com/a.png", Crig::Completion::ImageMediaType::PNG, Crig::Completion::ImageDetail::High, params)
    base64 = Crig::Completion::Image.base64("Zm9v", Crig::Completion::ImageMediaType::PNG, Crig::Completion::ImageDetail::Low)
    raw = Crig::Completion::Image.raw(Bytes[1_u8, 2_u8], Crig::Completion::ImageMediaType::PNG)
    string = Crig::Completion::Image.string("hello", Crig::Completion::ImageMediaType::PNG)

    url.data.kind.url?.should be_true
    url.media_type.should eq(Crig::Completion::ImageMediaType::PNG)
    url.detail.should eq(Crig::Completion::ImageDetail::High)
    url.additional_params.should eq(params)
    base64.data.kind.base64?.should be_true
    base64.detail.should eq(Crig::Completion::ImageDetail::Low)
    raw.data.kind.raw?.should be_true
    string.data.kind.string?.should be_true
  end
end

describe Crig::Completion::UserContent, tags: %w[completion content] do
  it "builds multimedia helpers" do
    image = Crig::Completion::UserContent.image_url("https://example.com/a.png", Crig::Completion::ImageMediaType::PNG)
    audio = Crig::Completion::UserContent.audio("Zm9v", Crig::Completion::AudioMediaType::MP3)
    document = Crig::Completion::UserContent.document("hello", Crig::Completion::DocumentMediaType::TXT)
    video = Crig::Completion::UserContent.video_url("https://example.com/a.mp4", Crig::Completion::VideoMediaType::MP4)

    image.kind.image?.should be_true
    image.image.as(Crig::Completion::Image).try_into_url.should eq("https://example.com/a.png")
    audio.kind.audio?.should be_true
    document.kind.document?.should be_true
    video.kind.video?.should be_true
    Crig::Completion::DocumentMediaType::Javascript.is_code.should be_true
  end
end

describe Crig::Completion::AssistantContent, tags: %w[completion content] do
  it "builds helper content variants" do
    text = Crig::Completion::AssistantContent.text("hello")
    tool_call = Crig::Completion::AssistantContent.tool_call("tool-1", "weather", JSON.parse(%({"city":"Paris"})))
    reasoning = Crig::Completion::AssistantContent.reasoning("thinking")
    image = Crig::Completion::AssistantContent.image_base64("Zm9v", Crig::Completion::ImageMediaType::PNG)

    text.kind.text?.should be_true
    tool_call.kind.tool_call?.should be_true
    tool_call.tool_call.not_nil!.function.name.should eq("weather")
    reasoning.kind.reasoning?.should be_true
    reasoning.reasoning.not_nil!.first_text.should eq("thinking")
    image.kind.image?.should be_true
    image.image.should_not be_nil
  end
end

describe Crig::Completion::DocumentSourceKind do
  it "supports source helpers and inner extraction" do
    url = Crig::Completion::DocumentSourceKind.url("https://example.com/file")
    base64 = Crig::Completion::DocumentSourceKind.base64("Zm9v")
    string = Crig::Completion::DocumentSourceKind.string("hello")
    unknown = Crig::Completion::DocumentSourceKind.unknown

    url.try_into_inner.should eq("https://example.com/file")
    base64.try_into_inner.should eq("Zm9v")
    string.try_into_inner.should eq("hello")
    unknown.try_into_inner.should be_nil
  end

  it "converts base64 images into data urls" do
    image = Crig::Completion::Image.new(
      Crig::Completion::DocumentSourceKind.base64("Zm9v"),
      Crig::Completion::ImageMediaType::PNG,
    )

    image.try_into_url.should eq("data:image/png;base64,Zm9v")
  end

  it "raises message errors for unsupported image url conversions" do
    expect_raises(Crig::Completion::MessageError, /media type is required/) do
      Crig::Completion::Image.base64("Zm9v").try_into_url
    end

    expect_raises(Crig::Completion::MessageError, /unknown type/) do
      Crig::Completion::Image.raw(Bytes[1_u8, 2_u8], Crig::Completion::ImageMediaType::PNG).try_into_url
    end
  end
end

describe Crig::Completion::Audio do
  it "builds wrapper helpers for common source kinds" do
    url = Crig::Completion::Audio.url("https://example.com/a.mp3", Crig::Completion::AudioMediaType::MP3)
    base64 = Crig::Completion::Audio.base64("Zm9v", Crig::Completion::AudioMediaType::MP3)
    raw = Crig::Completion::Audio.raw(Bytes[1_u8, 2_u8], Crig::Completion::AudioMediaType::WAV)
    string = Crig::Completion::Audio.string("hello", Crig::Completion::AudioMediaType::AAC)

    url.data.kind.url?.should be_true
    base64.data.kind.base64?.should be_true
    raw.data.kind.raw?.should be_true
    string.data.kind.string?.should be_true
  end
end

describe Crig::Completion::Video do
  it "builds wrapper helpers for common source kinds" do
    url = Crig::Completion::Video.url("https://example.com/a.mp4", Crig::Completion::VideoMediaType::MP4)
    base64 = Crig::Completion::Video.base64("Zm9v", Crig::Completion::VideoMediaType::WEBM)
    raw = Crig::Completion::Video.raw(Bytes[1_u8, 2_u8], Crig::Completion::VideoMediaType::MOV)
    string = Crig::Completion::Video.string("hello", Crig::Completion::VideoMediaType::AVI)

    url.data.kind.url?.should be_true
    base64.data.kind.base64?.should be_true
    raw.data.kind.raw?.should be_true
    string.data.kind.string?.should be_true
  end
end

describe Crig::Completion::Document do
  it "builds wrapper helpers for common source kinds" do
    url = Crig::Completion::Document.url("https://example.com/a.pdf", Crig::Completion::DocumentMediaType::PDF)
    base64 = Crig::Completion::Document.base64("Zm9v", Crig::Completion::DocumentMediaType::TXT)
    raw = Crig::Completion::Document.raw(Bytes[1_u8, 2_u8], Crig::Completion::DocumentMediaType::CSV)
    string = Crig::Completion::Document.string("hello", Crig::Completion::DocumentMediaType::MARKDOWN)

    url.data.kind.url?.should be_true
    base64.data.kind.base64?.should be_true
    raw.data.kind.raw?.should be_true
    string.data.kind.string?.should be_true
  end
end

describe Crig::Completion::Message, tags: %w[completion message] do
  it "supports conversion helpers from typed content" do
    text_message = Crig::Completion::Message.from(Crig::Completion::Text.new("hello"))
    image_message = Crig::Completion::Message.from(
      Crig::Completion::Image.new(
        Crig::Completion::DocumentSourceKind.url("https://example.com/a.png"),
        Crig::Completion::ImageMediaType::PNG,
      )
    )

    text_message.role.user?.should be_true
    text_message.rag_text.should eq("hello")
    image_message.role.user?.should be_true
  end

  it "supports additional upstream-style message conversions" do
    string_message = Crig::Completion::Message.from("hello")
    tool_result_message = Crig::Completion::Message.from(
      Crig::Completion::ToolResultContent.text("done")
    )
    assistant_message = Crig::Completion::Message.from(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("hi")
      )
    )

    string_message.role.user?.should be_true
    string_message.rag_text.should eq("hello")

    tool_result_message.role.user?.should be_true
    tool_result = tool_result_message.content.first.as(Crig::Completion::UserContent).tool_result
    tool_result.should_not be_nil
    tool_result.as(Crig::Completion::ToolResult).id.should eq("")
    tool_result.as(Crig::Completion::ToolResult).content.first.kind.text?.should be_true

    assistant_message.role.assistant?.should be_true
    assistant_message.content.first.as(Crig::Completion::AssistantContent).kind.text?.should be_true
  end
end
