require "../../spec_helper"
describe Crig::Providers::Mistral do
  it "supports client initialization" do
    client = Crig::Providers::Mistral::Client.new("dummy-key")
    client_from_builder = Crig::Providers::Mistral::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::Mistral::MISTRAL_API_BASE_URL)
  end

  it "deserializes completion responses" do
    response = Crig::Providers::Mistral::CompletionResponse.from_json(%(
      {"id":"cmpl-e5cc70bb28c444948073e77776eb30ef","object":"chat.completion","model":"mistral-small-latest","usage":{"prompt_tokens":16,"completion_tokens":34,"total_tokens":50},"created":1702256327,"choices":[{"index":0,"message":{"content":"string","tool_calls":[{"id":"null","type":"function","function":{"name":"string","arguments":"{ }"},"index":0}],"prefix":false,"role":"assistant"},"finish_reason":"stop"}]}
    ))

    response.model.should eq(Crig::Providers::Mistral::MISTRAL_SMALL)
    response.id.should eq("cmpl-e5cc70bb28c444948073e77776eb30ef")
    response.usage.not_nil!.prompt_tokens.should eq(16)
    response.usage.not_nil!.completion_tokens.should eq(34)
    response.usage.not_nil!.total_tokens.should eq(50)
    response.choices.size.should eq(1)
  end

  it "skips assistant reasoning during message conversion" do
    assistant = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
      ),
    )

    Crig::Providers::Mistral::Message.from_core_message(assistant).should eq([] of Crig::Providers::Mistral::Message)
  end

  it "preserves assistant text and tool calls when reasoning is present" do
    assistant = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.text("visible").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.tool_call("call_1", "subtract", JSON.parse(%({"x":2,"y":1}))).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    converted = Crig::Providers::Mistral::Message.from_core_message(assistant)

    converted.size.should eq(1)
    converted[0].content.should eq("visible")
    converted[0].tool_calls.size.should eq(1)
    converted[0].tool_calls[0].id.should eq("call_1")
    converted[0].tool_calls[0].function.name.should eq("subtract")
    converted[0].tool_calls[0].function.arguments["x"].as_i.should eq(2)
  end

  it "maps streaming assistant content while skipping reasoning" do
    Crig::Providers::Mistral.assistant_content_to_streaming_choice(
      Crig::Completion::AssistantContent.reasoning("hidden")
    ).should be_nil

    text_choice = Crig::Providers::Mistral.assistant_content_to_streaming_choice(
      Crig::Completion::AssistantContent.text("visible")
    )
    text_choice.should eq(Crig::RawStreamingChoice(Crig::Providers::Mistral::CompletionResponse).message("visible"))

    tool_choice = Crig::Providers::Mistral.assistant_content_to_streaming_choice(
      Crig::Completion::AssistantContent.tool_call("call_2", "add", JSON.parse(%({"x":2,"y":3})))
    )
    tool_choice.should_not be_nil
    tool_choice.not_nil!.kind.tool_call?.should be_true
    tool_choice.not_nil!.tool_call.not_nil!.id.should eq("call_2")
    tool_choice.not_nil!.tool_call.not_nil!.name.should eq("add")
    tool_choice.not_nil!.tool_call.not_nil!.arguments.should eq(JSON.parse(%({"x":2,"y":3})))
  end

  it "errors when all request messages are filtered out" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(
        Crig::Completion::Message.new(
          Crig::Completion::Message::Role::Assistant,
          Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
            Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
          ),
        )
      ),
    )

    expect_raises(Crig::Completion::CompletionError, "Mistral request has no provider-compatible messages after conversion") do
      Crig::Providers::Mistral::MistralCompletionRequest.from_request(Crig::Providers::Mistral::MISTRAL_SMALL, request)
    end
  end

  it "deserializes mistral transcription responses" do
    response = Crig::Providers::Mistral::MistralTranscriptionResponse.from_json(%(
      {"model":"voxtral-mini-latest","text":"The sun was setting slowly, casting long shadows across the empty field.","language":null,"segments":[{"text":"The sun was setting slowly, casting long shadows across the empty field.","start":0.2,"end":4.6,"speaker_id":"speaker_1","type":"transcription_segment"}],"usage":{"prompt_audio_seconds":5,"prompt_tokens":5,"total_tokens":404,"completion_tokens":24,"prompt_tokens_details":{"cached_tokens":368}},"finish_reason":null}
    ))

    response.language.should be_nil
    response.model.should eq(Crig::Providers::Mistral::VOXTRAL_MINI)
    response.segments.size.should eq(1)
    response.segments[0].start.should eq(0.2_f32)
    response.segments[0].end.should eq(4.6_f32)
    response.segments[0].speaker_id.should eq("speaker_1")
    response.segments[0].segment_type.should eq("transcription_segment")
    response.usage.prompt_audio_seconds.should eq(5)
    response.usage.prompt_tokens.should eq(5)
    response.usage.total_tokens.should eq(404)
    response.usage.prompt_tokens_details.not_nil!["cached_tokens"].as_i.should eq(368)
  end

  it "converts mistral transcription responses into core responses" do
    mistral_response = Crig::Providers::Mistral::MistralTranscriptionResponse.new(
      model: Crig::Providers::Mistral::VOXTRAL_MINI,
      segments: [
        Crig::Providers::Mistral::SegmentChunk.new(
          0.0_f32,
          1.0_f32,
          "Lorem Ipsum is simply dummy text of the printing and typesetting industry.",
          segment_type: "speech",
        ),
      ],
      text: "Lorem Ipsum is simply dummy text of the printing and typesetting industry.",
      usage: Crig::Providers::Mistral::TranscriptionUsage.new(
        prompt_audio_seconds: 1,
        prompt_tokens: 10,
        total_tokens: 20,
        completion_tokens: 10,
      ),
      language: "en",
    )

    response = mistral_response.to_crig_response

    response.text.should eq("Lorem Ipsum is simply dummy text of the printing and typesetting industry.")
    response.response.model.should eq(Crig::Providers::Mistral::VOXTRAL_MINI)
    response.response.language.should eq("en")
  end
end
