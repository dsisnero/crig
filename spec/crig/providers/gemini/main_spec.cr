require "../../../spec_helper"
describe Crig::Providers::Gemini::Client do
  it "ports the gemini client initialization" do
    client = Crig::Providers::Gemini::Client.new("dummy-key")
    builder_client = Crig::Providers::Gemini::Client.builder.api_key("dummy-key").build

    client.ext.api_key.should eq("dummy-key")
    builder_client.ext.api_key.should eq("dummy-key")
    client.build_uri("/v1beta/models").should eq("https://generativelanguage.googleapis.com/v1beta/models?key=dummy-key")
    client.build_uri("/v1beta/models", sse: true).should eq("https://generativelanguage.googleapis.com/v1beta/models?key=dummy-key&alt=sse")
  end

  it "converts between generate-content and interactions clients" do
    client = Crig::Providers::Gemini::Client.new("dummy-key")
    interactions = client.interactions_api
    round_trip = interactions.generate_content_api

    interactions.ext.api_key.should eq("dummy-key")
    interactions.build_uri("/v1beta/interactions").should eq("https://generativelanguage.googleapis.com/v1beta/interactions")
    interactions.build_uri("/v1beta/interactions?foo=bar", sse: true).should eq("https://generativelanguage.googleapis.com/v1beta/interactions?foo=bar&alt=sse")
    round_trip.ext.api_key.should eq("dummy-key")
  end
end

describe Crig::Providers::Gemini do
  it "ports the gemini completion constants and endpoint helpers" do
    Crig::Providers::Gemini::GEMINI_2_5_FLASH.should eq("gemini-2.5-flash")
    Crig::Providers::Gemini.completion_endpoint("gemini-2.5-flash").should eq("/v1beta/models/gemini-2.5-flash:generateContent")
    Crig::Providers::Gemini.streaming_endpoint("gemini-2.5-flash").should eq("/v1beta/models/gemini-2.5-flash:streamGenerateContent")
  end

  it "resolves the request model override and default" do
    default_request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("hello")
      .build
    override_request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("hello")
      .model("google/gemini-2.5-flash")
      .build

    Crig::Providers::Gemini.resolve_request_model(Crig::Providers::Gemini::GEMINI_2_0_FLASH, default_request).should eq(Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    Crig::Providers::Gemini.resolve_request_model(Crig::Providers::Gemini::GEMINI_2_0_FLASH, override_request).should eq("google/gemini-2.5-flash")
  end
end

describe Crig::Providers::Gemini::AdditionalParameters do
  it "ports the additional-parameters helper methods" do
    config = Crig::Providers::Gemini::GenerationConfig.new
    params = Crig::Providers::Gemini::AdditionalParameters.new
      .with_config(config)
      .with_params(JSON.parse(%({"candidateCount":2})))

    params.generation_config.should eq(config)
    params.additional_params.not_nil!["candidateCount"].as_i.should eq(2)
  end

  it "round-trips the broader generation-config field set" do
    config = Crig::Providers::Gemini::GenerationConfig.from_json(%({
      "stopSequences":["DONE","STOP"],
      "responseMimeType":"application/json",
      "responseSchema":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]},
      "_responseJsonSchema":{"type":"object","properties":{"age":{"type":"integer"}}},
      "responseJsonSchema":{"type":"object","properties":{"city":{"type":"string"}}},
      "candidateCount":1,
      "maxOutputTokens":64,
      "temperature":0.2,
      "topP":0.9,
      "topK":20,
      "presencePenalty":0.1,
      "frequencyPenalty":0.3,
      "responseLogprobs":true,
      "logprobs":5
    }))

    config.stop_sequences.should eq(["DONE", "STOP"])
    config.response_mime_type.should eq("application/json")
    config.response_schema.not_nil!.type.should eq("object")
    config.response_schema.not_nil!.properties.not_nil!["name"].type.should eq("string")
    config.internal_response_json_schema.not_nil!["properties"]["age"]["type"].as_s.should eq("integer")
    config.response_json_schema.not_nil!["properties"]["city"]["type"].as_s.should eq("string")
    config.candidate_count.should eq(1)
    config.max_output_tokens.should eq(64_i64)
    config.temperature.should eq(0.2)
    config.top_p.should eq(0.9)
    config.top_k.should eq(20)
    config.presence_penalty.should eq(0.1)
    config.frequency_penalty.should eq(0.3)
    config.response_logprobs.should be_true
    config.logprobs.should eq(5)
    config.empty?.should be_false

    roundtrip = JSON.parse(config.to_json)
    roundtrip["stopSequences"].as_a.map(&.as_s).should eq(["DONE", "STOP"])
    roundtrip["responseSchema"]["properties"]["name"]["type"].as_s.should eq("string")
    roundtrip["_responseJsonSchema"]["properties"]["age"]["type"].as_s.should eq("integer")
    roundtrip["responseJsonSchema"]["properties"]["city"]["type"].as_s.should eq("string")
    roundtrip["responseLogprobs"].as_bool.should be_true
    roundtrip["logprobs"].as_i.should eq(5)
  end
end

describe Crig::Providers::Gemini::CompletionModel do
  it "supports the class-level with_model helper" do
    client = Crig::Providers::Gemini::Client.new("dummy-key")
    model = Crig::Providers::Gemini::CompletionModel.with_model(client, Crig::Providers::Gemini::GEMINI_2_0_FLASH)

    model.client.should eq(client)
    model.model.should eq(Crig::Providers::Gemini::GEMINI_2_0_FLASH)
  end
end

describe Crig::Providers::Gemini::Content do
  it "deserializes a user message" do
    content = Crig::Providers::Gemini::Content.from_json(%({
      "parts": [
        {"text": "Hello, world!"},
        {"inlineData": {"mimeType": "image/png", "data": "base64encodeddata"}},
        {"functionCall": {"name": "test_function", "args": {"arg1": "value1"}}},
        {"functionResponse": {"name": "test_function", "response": {"result": "success"}}},
        {"fileData": {"mimeType": "application/pdf", "fileUri": "http://example.com/file.pdf"}},
        {"executableCode": {"code": "print('Hello, world!')", "language": "PYTHON"}},
        {"codeExecutionResult": {"output": "Hello, world!", "outcome": "OUTCOME_OK"}}
      ],
      "role": "user"
    }))

    content.role.should eq(Crig::Providers::Gemini::Role::User)
    content.parts.size.should eq(7)
    content.parts[0].part.kind.text?.should be_true
    content.parts[0].part.text.should eq("Hello, world!")
    content.parts[1].part.kind.inline_data?.should be_true
    content.parts[1].part.inline_data.not_nil!.mime_type.should eq("image/png")
    content.parts[2].part.function_call.not_nil!.name.should eq("test_function")
    content.parts[2].part.function_call.not_nil!.args["arg1"].as_s.should eq("value1")
    content.parts[3].part.function_response.not_nil!.response.not_nil!["result"].as_s.should eq("success")
    content.parts[4].part.file_data.not_nil!.file_uri.should eq("http://example.com/file.pdf")
    content.parts[5].part.executable_code.not_nil!.code.should eq("print('Hello, world!')")
    content.parts[6].part.code_execution_result.not_nil!.output.should eq("Hello, world!")
  end

  it "deserializes a model message" do
    content = Crig::Providers::Gemini::Content.from_json(%({
      "parts": [{"text": "Hello, user!"}],
      "role": "model"
    }))

    content.role.should eq(Crig::Providers::Gemini::Role::Model)
    content.parts.size.should eq(1)
    content.parts.first.part.text.should eq("Hello, user!")
  end

  it "emits the reasoning signature in a gemini part" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: Crig::Completion::Reasoning.new_with_signature("structured thought", "reuse_sig_456"),
        ).as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
      ),
    )

    content = Crig::Providers::Gemini::Content.from_message(message)
    first = content.parts.first

    first.thought.should be_true
    first.thought_signature.should eq("reuse_sig_456")
    first.part.kind.text?.should be_true
    first.part.text.should eq("structured thought")
  end

  it "converts a user message into gemini content" do
    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.user("Hello, world!"))

    content.role.should eq(Crig::Providers::Gemini::Role::User)
    content.parts.size.should eq(1)
    content.parts.first.part.kind.text?.should be_true
    content.parts.first.part.text.should eq("Hello, world!")
  end

  it "converts an assistant message into gemini content" do
    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.assistant("Hello, user!"))

    content.role.should eq(Crig::Providers::Gemini::Role::Model)
    content.parts.size.should eq(1)
    content.parts.first.part.kind.text?.should be_true
    content.parts.first.part.text.should eq("Hello, user!")
  end

  it "converts an assistant tool call into a gemini function call part" do
    message = Crig::Completion::Message.from(
      Crig::Completion::ToolCall.new(
        "test_tool",
        Crig::Completion::ToolFunction.new("test_function", JSON.parse(%({"arg1":"value1"}))),
      )
    )

    content = Crig::Providers::Gemini::Content.from_message(message)

    content.role.should eq(Crig::Providers::Gemini::Role::Model)
    content.parts.size.should eq(1)
    function_call = content.parts.first.part.function_call.not_nil!
    function_call.name.should eq("test_function")
    function_call.args["arg1"].as_s.should eq("value1")
  end

  it "converts txt documents into text parts" do
    document = Crig::Completion::UserContent.new(
      Crig::Completion::UserContent::Kind::Document,
      document: Crig::Completion::Document.new(
        Crig::Completion::DocumentSourceKind.string("Note: test.md\nPath: /test.md\nContent: Hello World!"),
        Crig::Completion::DocumentMediaType::TXT,
      ),
    )

    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.from(document))

    content.parts.first.part.kind.text?.should be_true
    content.parts.first.part.text.not_nil!.includes?("Note: test.md").should be_true
    content.parts.first.part.text.not_nil!.includes?("Hello World!").should be_true
  end

  it "converts markdown documents into text parts" do
    document = Crig::Completion::UserContent.new(
      Crig::Completion::UserContent::Kind::Document,
      document: Crig::Completion::Document.new(
        Crig::Completion::DocumentSourceKind.string("# Heading\n\n* List item"),
        Crig::Completion::DocumentMediaType::MARKDOWN,
      ),
    )

    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.from(document))

    content.parts.first.part.kind.text?.should be_true
    content.parts.first.part.text.should eq("# Heading\n\n* List item")
  end

  it "converts url-backed markdown documents into file data parts" do
    document = Crig::Completion::UserContent.new(
      Crig::Completion::UserContent::Kind::Document,
      document: Crig::Completion::Document.new(
        Crig::Completion::DocumentSourceKind.url("https://generativelanguage.googleapis.com/v1beta/files/test-markdown"),
        Crig::Completion::DocumentMediaType::MARKDOWN,
      ),
    )

    content = Crig::Providers::Gemini::Content.from_message(Crig::Completion::Message.from(document))

    file_data = content.parts.first.part.file_data.not_nil!
    file_data.file_uri.should eq("https://generativelanguage.googleapis.com/v1beta/files/test-markdown")
    file_data.mime_type.should eq("text/markdown")
  end

  it "converts tool results with image content" do
    content = Crig::Providers::Gemini::Content.from_message(
      Crig::Completion::Message.from(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::ToolResult,
          tool_result: Crig::Completion::ToolResult.new(
            "test_tool",
            Crig::OneOrMany(Crig::Completion::ToolResultContent).many([
              Crig::Completion::ToolResultContent.text(%({"status":"success"})),
              Crig::Completion::ToolResultContent.image_base64(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
                Crig::Completion::ImageMediaType::PNG,
              ),
            ])
          ),
        )
      )
    )

    function_response = content.parts.first.part.function_response.not_nil!
    function_response.name.should eq("test_tool")
    function_response.response.should_not be_nil
    function_response.response.not_nil!["result"]["status"].as_s.should eq("success")
    function_response.parts.should_not be_nil
    function_response.parts.not_nil!.size.should eq(1)
    function_response.parts.not_nil!.first.inline_data.not_nil!.mime_type.should eq("image/png")
  end

  it "converts tool results with url images into file data parts" do
    content = Crig::Providers::Gemini::Content.from_message(
      Crig::Completion::Message.from(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::ToolResult,
          tool_result: Crig::Completion::ToolResult.new(
            "screenshot_tool",
            Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
              Crig::Completion::ToolResultContent.image_url(
                "https://example.com/image.png",
                Crig::Completion::ImageMediaType::PNG,
              )
            )
          ),
        )
      )
    )

    function_response = content.parts.first.part.function_response.not_nil!
    function_response.name.should eq("screenshot_tool")
    file_data = function_response.parts.not_nil!.first.file_data.not_nil!
    file_data.file_uri.should eq("https://example.com/image.png")
    file_data.mime_type.should eq("image/png")
  end
end

describe Crig::Providers::Gemini::Schema do
  it "ports the object schema conversion" do
    schema = Crig::Providers::Gemini::Schema.try_from(JSON.parse(%({
      "type": "object",
      "properties": {
        "name": {"type": "string"}
      }
    })))

    schema.type.should eq("object")
    schema.properties.should_not be_nil
    schema.properties.not_nil!.has_key?("name").should be_true
  end

  it "ports arrays with inline items" do
    schema = Crig::Providers::Gemini::Schema.try_from(JSON.parse(%({
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": {"type": "string"}
        }
      }
    })))

    schema.type.should eq("array")
    schema.items.should_not be_nil
    schema.items.not_nil!.type.should eq("object")
    schema.items.not_nil!.properties.should_not be_nil
  end

  it "flattens referenced schemas" do
    flattened = Crig::Providers::Gemini.flatten_schema(JSON.parse(%({
      "type": "array",
      "items": {"$ref": "#/$defs/Person"},
      "$defs": {
        "Person": {
          "type": "object",
          "properties": {
            "name": {"type": "string"}
          }
        }
      }
    })))

    schema = Crig::Providers::Gemini::Schema.try_from(flattened)
    schema.type.should eq("array")
    schema.items.should_not be_nil
    schema.items.not_nil!.type.should eq("object")
    schema.items.not_nil!.properties.should_not be_nil
  end

  it "adds default string items to arrays without items" do
    schema = Crig::Providers::Gemini::Schema.try_from(JSON.parse(%({
      "type": "object",
      "properties": {
        "service_ids": {
          "type": "array",
          "description": "A list of service IDs"
        }
      }
    })))

    service_ids = schema.properties.not_nil!["service_ids"]
    service_ids.type.should eq("array")
    service_ids.items.should_not be_nil
    service_ids.items.not_nil!.type.should eq("string")
  end
end

describe Crig::Providers::Gemini::GenerateContentResponse do
  it "preserves thought signatures from response reasoning parts" do
    response = Crig::Providers::Gemini::GenerateContentResponse.new(
      "resp_1",
      [
        Crig::Providers::Gemini::ContentCandidate.new(
          content: Crig::Providers::Gemini::Content.new(
            [
              Crig::Providers::Gemini::Part.new(
                Crig::Providers::Gemini::PartKind.text("thinking text"),
                thought: true,
                thought_signature: "thought_sig_123",
              ),
            ],
            role: Crig::Providers::Gemini::Role::Model,
          ),
          finish_reason: Crig::Providers::Gemini::FinishReason::Stop,
        ),
      ],
    )

    converted = response.to_completion_response
    reasoning = converted.choice.first.reasoning.not_nil!
    reasoning.first_text.should eq("thinking text")
    reasoning.first_signature.should eq("thought_sig_123")
  end

  it "deserializes prompt feedback, safety, citation, and logprob metadata" do
    response = Crig::Providers::Gemini::GenerateContentResponse.from_json(%({
      "responseId":"resp_meta",
      "promptFeedback":{
        "blockReason":"SAFETY",
        "safetyRatings":[
          {"category":"HARM_CATEGORY_HATE_SPEECH","probability":"HIGH"}
        ]
      },
      "candidates":[
        {
          "content":{"parts":[{"text":"hello"}],"role":"model"},
          "finishReason":"STOP",
          "safetyRatings":[
            {"category":"HARM_CATEGORY_DANGEROUS_CONTENT","probability":"LOW"}
          ],
          "citationMetadata":{
            "citationSources":[
              {"uri":"https://example.com","startIndex":0,"endIndex":5,"license":"CC-BY"}
            ]
          },
          "tokenCount":4,
          "avgLogprobs":-0.25,
          "logprobsResult":{
            "topCandidates":[
              {"candidates":[{"token":"hello","tokenId":"1","logProbability":-0.25}]}
            ],
            "chosenCandidates":[
              {"token":"hello","tokenId":"1","logProbability":-0.25}
            ]
          },
          "index":0,
          "finishMessage":"done"
        }
      ],
      "usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}
    }))

    response.prompt_feedback.not_nil!.block_reason.should eq(Crig::Providers::Gemini::BlockReason::Safety)
    response.prompt_feedback.not_nil!.safety_ratings.not_nil!.first.category.should eq(
      Crig::Providers::Gemini::HarmCategory::HarmCategoryHateSpeech
    )
    candidate = response.candidates.first
    candidate.safety_ratings.not_nil!.first.probability.should eq(Crig::Providers::Gemini::HarmProbability::Low)
    candidate.citation_metadata.not_nil!.citation_sources.first.uri.should eq("https://example.com")
    candidate.logprobs_result.not_nil!.chosen_candidates.first.token.should eq("hello")
    candidate.finish_message.should eq("done")
  end
end

describe Crig::Providers::Gemini::ExecutableCode do
  it "serializes execution language using the upstream wire values" do
    payload = JSON.parse(
      Crig::Providers::Gemini::ExecutableCode.new(
        Crig::Providers::Gemini::ExecutionLanguage::Python,
        "print('hi')"
      ).to_json
    )

    payload["language"].as_s.should eq("PYTHON")
    payload["code"].as_s.should eq("print('hi')")
  end
end

describe Crig::Providers::Gemini::CodeExecutionResult do
  it "deserializes code execution outcomes using the upstream wire values" do
    result = Crig::Providers::Gemini::CodeExecutionResult.from_json(%({
      "outcome":"OUTCOME_DEADLINE_EXCEEDED",
      "output":"partial output"
    }))

    result.outcome.should eq(Crig::Providers::Gemini::CodeExecutionOutcome::DeadlineExceeded)
    result.output.should eq("partial output")
  end
end

describe Crig::Providers::Gemini::TranscriptionModel do
  it "posts generateContent transcription requests and extracts the returned text" do
    server = FakeGeminiGenerateContentServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({"responseId":"resp","candidates":[{"content":{"parts":[{"text":"hello world"}],"role":"model"}}]}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("gemini-key", "http://127.0.0.1:#{address.port}")
    response = client.transcription_model("gemini-2.0-flash")
      .transcription(
        Crig::TranscriptionRequest.new(
          "abc".to_slice,
          "speech.wav",
          temperature: 0.2,
          additional_params: JSON.parse(%({"maxOutputTokens":64}))
        )
      )

    response.text.should eq("hello world")
    request = server.requests.first
    request["generationConfig"]["temperature"].as_f.should eq(0.2)
    request["generationConfig"]["maxOutputTokens"].as_i.should eq(64)
    request["systemInstruction"]["parts"][0]["text"].as_s.should eq(
      "Translate the provided audio exactly. Do not add additional information."
    )
    blob = request["contents"][0]["parts"][0]["inlineData"]
    blob["mimeType"].as_s.should eq("audio/wav")
    Base64.decode_string(blob["data"].as_s).should eq("abc")

    http_server.close
  end

  it "surfaces provider errors from generateContent" do
    server = FakeGeminiGenerateContentServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({"error":"bad transcription"}),
        status_code:  400,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("gemini-key", "http://127.0.0.1:#{address.port}")

    expect_raises(Crig::TranscriptionError, /bad transcription/) do
      client.transcription_model("gemini-2.0-flash")
        .transcription(Crig::TranscriptionRequest.new("abc".to_slice, "speech.unknown"))
    end

    http_server.close
  end
end

describe Crig::Providers::Gemini::StreamGenerateContentResponse do
  it "deserializes a stream response with single text part" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{"parts":[{"text":"Hello, world!"}],"role":"model"},
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15}
    }))

    response.candidates.size.should eq(1)
    response.candidates.first.content.not_nil!.parts.size.should eq(1)
    response.candidates.first.content.not_nil!.parts.first.part.text.should eq("Hello, world!")
  end

  it "deserializes a stream response with multiple text parts" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{"parts":[{"text":"Hello, "},{"text":"world!"},{"text":" How are you?"}],"role":"model"},
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":8,"totalTokenCount":18}
    }))

    parts = response.candidates.first.content.not_nil!.parts
    parts.map { |part| part.part.text }.should eq(["Hello, ", "world!", " How are you?"])
  end

  it "deserializes a stream response with multiple tool calls" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{
          "parts":[
            {"functionCall":{"name":"get_weather","args":{"city":"San Francisco"}}},
            {"functionCall":{"name":"get_temperature","args":{"location":"New York"}}}
          ],
          "role":"model"
        },
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":20,"totalTokenCount":70}
    }))

    parts = response.candidates.first.content.not_nil!.parts
    parts[0].part.function_call.not_nil!.name.should eq("get_weather")
    parts[1].part.function_call.not_nil!.name.should eq("get_temperature")
  end

  it "deserializes a stream response with mixed parts" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{
          "parts":[
            {"text":"Let me think about this...","thought":true},
            {"text":"Here's my response: "},
            {"functionCall":{"name":"search","args":{"query":"rust async"}}},
            {"text":"I found the answer!"}
          ],
          "role":"model"
        },
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":50,"thoughtsTokenCount":15,"totalTokenCount":165}
    }))

    parts = response.candidates.first.content.not_nil!.parts
    parts.size.should eq(4)
    parts[0].thought.should be_true
    parts[0].part.text.should eq("Let me think about this...")
    parts[1].part.text.should eq("Here's my response: ")
    parts[2].part.function_call.not_nil!.name.should eq("search")
    parts[3].part.text.should eq("I found the answer!")
  end

  it "deserializes a stream response with empty parts" do
    response = Crig::Providers::Gemini::StreamGenerateContentResponse.from_json(%({
      "candidates":[{
        "content":{"parts":[],"role":"model"},
        "finishReason":"Stop"
      }],
      "usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":0,"totalTokenCount":10}
    }))

    response.candidates.first.content.not_nil!.parts.should be_empty
  end
end

describe Crig::Providers::Gemini::PartialUsage do
  it "calculates token usage" do
    usage = Crig::Providers::Gemini::PartialUsage.new(
      total_token_count: 100,
      cached_content_token_count: 20,
      candidates_token_count: 30,
      thoughts_token_count: 10,
      prompt_token_count: 40,
    )

    token_usage = usage.token_usage
    token_usage.input_tokens.should eq(40)
    token_usage.output_tokens.should eq(60)
    token_usage.total_tokens.should eq(100)
  end

  it "calculates token usage with missing counts" do
    usage = Crig::Providers::Gemini::PartialUsage.new(
      total_token_count: 40,
      prompt_token_count: 40,
    )

    token_usage = usage.token_usage
    token_usage.input_tokens.should eq(40)
    token_usage.output_tokens.should eq(0)
    token_usage.total_tokens.should eq(40)
  end
end

describe Crig::Providers::Gemini::StreamingCompletionResponse do
  it "converts partial usage into token usage" do
    response = Crig::Providers::Gemini::StreamingCompletionResponse.new(
      Crig::Providers::Gemini::PartialUsage.new(
        total_token_count: 15,
        candidates_token_count: 5,
        prompt_token_count: 10,
      )
    )

    token_usage = response.token_usage
    token_usage.input_tokens.should eq(10)
    token_usage.output_tokens.should eq(5)
    token_usage.total_tokens.should eq(15)
  end
end

describe Crig::Providers::Together::ApiErrorResponse do
  it "formats provider errors with the upstream code prefix" do
    Crig::Providers::Together::ApiErrorResponse.new("bad request", "invalid_request_error").message
      .should eq("Code `invalid_request_error`: bad request")
  end
end

describe Crig::Providers::Together::Client do
  it "initializes directly and from the builder" do
    direct = Crig::Providers::Together::Client.new("dummy-key")
    built = Crig::Providers::Together::Client.builder.api_key("dummy-key").build

    direct.api_key.token.should eq("dummy-key")
    built.api_key.token.should eq("dummy-key")
    built.base_url.should eq(Crig::Providers::Together::TOGETHER_AI_BASE_URL)
  end
end

describe Crig::Providers::Together::ToolChoice do
  it "maps specific tool choices into together function lists" do
    choice = Crig::Providers::Together::ToolChoice.from_core(
      Crig::Completion::ToolChoice.specific(["search", "lookup"])
    )

    choice.kind.function?.should be_true
    choice.functions.map(&.name).should eq(["search", "lookup"])
    choice.to_json_value.to_json.should eq(%([{"type":"function","function":{"name":"search"}},{"type":"function","function":{"name":"lookup"}}]))
  end
end

describe Crig::Providers::Together::TogetherAICompletionRequest do
  it "errors when all converted messages are filtered out" do
    request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(
        Crig::Completion::Message.new(
          Crig::Completion::Message::Role::Assistant,
          Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
            Crig::Completion::AssistantContent.reasoning("hidden")
          )
        )
      ),
    )

    expect_raises(Crig::Completion::CompletionError, "Together request has no provider-compatible messages after conversion") do
      Crig::Providers::Together::TogetherAICompletionRequest.from_request("meta-llama/test-model", request)
    end
  end
end

describe Crig::Providers::Gemini::EmbeddingModel do
  it "posts batch embed requests and returns embeddings" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.status_code = 200
      context.response.content_type = "application/json"
      context.response.print(%({
        "embeddings":[
          {"values":[0.1,0.2]},
          {"values":[0.3,0.4]}
        ]
      }))
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.embedding_model_with_ndims(Crig::Providers::Gemini::EMBEDDING_004, 2)
    embeddings = model.embed_texts(["hello", "world"])

    embeddings.map(&.document).should eq(["hello", "world"])
    embeddings[0].vec.should eq([0.1, 0.2])
    embeddings[1].vec.should eq([0.3, 0.4])

    payload = requests.first
    payload["requests"].as_a.size.should eq(2)
    payload["requests"].as_a.first["model"].as_s.should eq("models/#{Crig::Providers::Gemini::EMBEDDING_004}")
    payload["requests"].as_a.first["content"]["parts"].as_a.first["text"].as_s.should eq("hello")
    payload["requests"].as_a.first["outputDimensionality"].as_i.should eq(2)

    http_server.close
  end

  it "uses default and explicit embedding dimensions like upstream" do
    client = Crig::Providers::Gemini::Client.new("test-key")

    default_model = client.embedding_model(Crig::Providers::Gemini::EMBEDDING_001)
    explicit_model = client.embedding_model_with_ndims(Crig::Providers::Gemini::EMBEDDING_001, 256)

    default_model.ndims.should eq(3072)
    explicit_model.ndims.should eq(256)
    default_model.max_documents.should eq(1024)
  end
end

describe Crig::Completion::ToolResultContent, tags: %w[completion content] do
  it "parses image json tool output" do
    result = Crig::Completion::ToolResultContent.from_tool_output(%({"type":"image","data":"base64data==","mimeType":"image/jpeg"}))

    result.len.should eq(1)
    item = result.first
    item.kind.image?.should be_true
    image = item.image.not_nil!
    image.data.kind.base64?.should be_true
    image.data.string_value.should eq("base64data==")
    image.media_type.should eq(Crig::Completion::ImageMediaType::JPEG)
  end

  it "parses hybrid response and image tool output" do
    result = Crig::Completion::ToolResultContent.from_tool_output(%({
      "response": {"status": "ok", "count": 42},
      "parts": [
        {"type": "image", "data": "imgdata1==", "mimeType": "image/png"},
        {"type": "image", "data": "https://example.com/img.jpg", "mimeType": "image/jpeg"}
      ]
    }))

    result.len.should eq(3)
    items = result.to_a
    items[0].kind.text?.should be_true
    items[0].text.not_nil!.text.includes?("status").should be_true
    items[1].kind.image?.should be_true
    items[1].image.not_nil!.data.kind.base64?.should be_true
    items[2].kind.image?.should be_true
    items[2].image.not_nil!.data.kind.url?.should be_true
  end
end

describe Crig::Providers::Gemini::CompletionModel do
  it "posts generate-content requests and returns converted assistant content" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.status_code = 200
      context.response.content_type = "application/json"
      context.response.print(%({
        "responseId":"resp_123",
        "candidates":[{
          "content":{"parts":[{"text":"hello"}],"role":"model"},
          "finishReason":"Stop"
        }],
        "usageMetadata":{
          "promptTokenCount":2,
          "candidatesTokenCount":1,
          "totalTokenCount":3
        }
      }))
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.completion_model(Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    response = model.completion(model.completion_request("Hello").build)

    response.choice.first.text.not_nil!.text.should eq("hello")
    response.usage.total_tokens.should eq(3)
    requests.first["contents"].as_a.first["parts"].as_a.first["text"].as_s.should eq("Hello")

    http_server.close
  end

  it "parses streaming text, reasoning, and tool call chunks" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.status_code = 200
      context.response.content_type = "text/event-stream"
      context.response.print <<-SSE
data: {"candidates":[{"content":{"parts":[{"text":"thinking","thought":true}],"role":"model"}}],"usageMetadata":{"promptTokenCount":3,"totalTokenCount":3}}

data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"search","args":{"query":"rust"}}}],"role":"model"}}],"usageMetadata":{"promptTokenCount":3,"totalTokenCount":3}}

data: {"candidates":[{"content":{"parts":[{"text":"done"}],"role":"model"},"finishReason":"Stop"}],"usageMetadata":{"promptTokenCount":3,"candidatesTokenCount":2,"thoughtsTokenCount":1,"totalTokenCount":6}}

data: [DONE]

SSE
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Gemini::GEMINI_2_0_FLASH).stream(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Search").build
    )

    items = [] of Crig::StreamedAssistantContent(Crig::Providers::Gemini::StreamingCompletionResponse)
    response.each_item { |item| items << item }

    items.any? { |item| item.kind.reasoning_delta? && item.reasoning_delta == "thinking" }.should be_true
    items.any? { |item| item.kind.text? && item.text.not_nil!.text == "done" }.should be_true
    items.any? { |item| item.kind.tool_call? && item.tool_call.not_nil!.function.name == "search" }.should be_true
    items.last.kind.final?.should be_true
    response.response.not_nil!.usage_metadata.total_token_count.should eq(6)
    requests.first["contents"].as_a.first["parts"].as_a.first["text"].as_s.should eq("Search")

    http_server.close
  end

  it "creates a request body with documents" do
    model = Crig::Providers::Gemini::CompletionModel.new(Crig::Providers::Gemini::Client.new("dummy-key"), Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("What are my notes about?")
      .preamble("You are a helpful assistant")
      .document(Crig::Completion::Request::Document.new("doc1", "Note: first.md\nContent: First note"))
      .document(Crig::Completion::Request::Document.new("doc2", "Note: second.md\nContent: Second note"))
      .build

    body = model.create_request_body(request)

    body.contents.size.should eq(2)
    body.contents[0].role.should eq(Crig::Providers::Gemini::Role::User)
    body.contents[0].parts.size.should eq(2)
    body.contents[0].parts.each do |part|
      part.part.kind.text?.should be_true
      part.part.text.not_nil!.includes?("Note:").should be_true
      part.part.text.not_nil!.includes?("Content:").should be_true
    end
    body.contents[1].role.should eq(Crig::Providers::Gemini::Role::User)
    body.contents[1].parts.first.part.text.should eq("What are my notes about?")
    body.system_instruction.not_nil!.role.should eq(Crig::Providers::Gemini::Role::Model)
  end

  it "creates a request body without documents" do
    model = Crig::Providers::Gemini::CompletionModel.new(Crig::Providers::Gemini::Client.new("dummy-key"), Crig::Providers::Gemini::GEMINI_2_0_FLASH)
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .preamble("You are a helpful assistant")
      .build

    body = model.create_request_body(request)

    body.contents.size.should eq(1)
    body.contents[0].role.should eq(Crig::Providers::Gemini::Role::User)
    body.contents[0].parts.first.part.text.should eq("Hello")
    body.system_instruction.not_nil!.parts.first.part.text.should eq("You are a helpful assistant")
  end
end

describe Crig::Providers::Gemini::Interactions do
  it "creates the simple interaction request body" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .preamble("Be precise.")
      .temperature(0.7)
      .max_tokens(128)
      .tool_choice(Crig::Completion::ToolChoice.required)
      .build

    result = Crig::Providers::Gemini::Interactions.create_request_body(
      "gemini-2.5-flash",
      request,
      false
    )

    result.model.should eq("gemini-2.5-flash")
    result.agent.should be_nil
    result.stream.should eq(false)
    result.system_instruction.should eq("Be precise.")

    config = result.generation_config.not_nil!
    config.temperature.should eq(0.7)
    config.max_output_tokens.should eq(128)
    config.tool_choice.not_nil!.kind.type?.should be_true
    config.tool_choice.not_nil!.type.should eq(Crig::Providers::Gemini::Interactions::ToolChoiceType::Any)

    result.input.kind.turns?.should be_true
    turn = result.input.turns.not_nil!.first
    turn.role.should eq(Crig::Providers::Gemini::Interactions::Role::User)
    turn.content.kind.contents?.should be_true
    content = turn.content.contents.not_nil!.first
    content.kind.text?.should be_true
    content.text.not_nil!.text.should eq("Hello")
  end

  it "requires call_id for tool result content" do
    content = Crig::Completion::UserContent.new(
      Crig::Completion::UserContent::Kind::ToolResult,
      tool_result: Crig::Completion::ToolResult.new(
        "get_weather",
        Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
          Crig::Completion::ToolResultContent.text("ok")
        )
      )
    )

    expect_raises(Crig::Completion::MessageError, /call_id/) do
      Crig::Providers::Gemini::Interactions::Content.from_user_content(content)
    end
  end

  it "maps response function calls into completion tool calls" do
    interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({
      "id":"interaction-1",
      "outputs":[{"type":"function_call","name":"get_weather","arguments":{"location":"Paris"},"id":"call-123"}],
      "usage":{"total_input_tokens":5,"total_output_tokens":7,"total_tokens":12}
    }))

    model = Crig::Providers::Gemini::Interactions::InteractionsCompletionModel.new(
      Crig::Providers::Gemini::InteractionsClient.new("dummy-key"),
      "gemini-2.5-flash"
    )
    response = model.interaction_to_completion_response(interaction)

    choice = response.choice.first
    choice.kind.tool_call?.should be_true
    choice.tool_call.not_nil!.function.name.should eq("get_weather")
    choice.tool_call.not_nil!.call_id.should eq("call-123")
    response.usage.input_tokens.should eq(5)
    response.usage.output_tokens.should eq(7)
    response.usage.total_tokens.should eq(12)
  end

  it "serializes google search, url context, and code execution tools" do
    JSON.parse(Crig::Providers::Gemini::Interactions::Tool.google_search.to_json)["type"].as_s.should eq("google_search")
    JSON.parse(Crig::Providers::Gemini::Interactions::Tool.url_context.to_json)["type"].as_s.should eq("url_context")
    JSON.parse(Crig::Providers::Gemini::Interactions::Tool.code_execution.to_json)["type"].as_s.should eq("code_execution")
  end

  it "groups google search helpers by call id" do
    interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({
      "outputs":[
        {"type":"google_search_call","arguments":{"queries":["query-one","query-two"]},"id":"call-1"},
        {"type":"google_search_result","result":[{"url":"https://example.com","title":"Example One"}],"call_id":"call-1"},
        {"type":"google_search_call","arguments":{"queries":["query-three"]},"id":"call-2"},
        {"type":"google_search_result","result":[{"url":"https://example.org","title":"Example Two"}],"call_id":"call-2"}
      ]
    }))

    exchanges = interaction.google_search_exchanges
    exchanges.size.should eq(2)
    exchanges[0].call_id.should eq("call-1")
    exchanges[0].queries.should eq(["query-one", "query-two"])
    exchanges[0].result_items.first.title.should eq("Example One")
    interaction.google_search_queries.should eq(["query-one", "query-two", "query-three"])
    interaction.google_search_results.map(&.title).should eq(["Example One", "Example Two"])
  end

  it "groups url context and code execution helpers without call ids by recency" do
    url_interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({
      "outputs":[
        {"type":"url_context_call","arguments":{"urls":["https://example.com"]}},
        {"type":"url_context_result","result":[{"url":"https://example.com","status":"success"}]},
        {"type":"url_context_call","arguments":{"urls":["https://example.org"]},"id":"call-2"},
        {"type":"url_context_result","result":[{"url":"https://example.org","status":"success"}]}
      ]
    }))
    url_interaction.url_context_exchanges.size.should eq(2)
    url_interaction.url_context_exchanges.find(&.call_id.nil?).not_nil!.results.size.should eq(1)
    url_interaction.url_context_exchanges.find { |exchange| exchange.call_id == "call-2" }.not_nil!.results.size.should eq(1)

    code_interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({
      "outputs":[
        {"type":"code_execution_call","arguments":{"language":"python","code":"print(1)"}},
        {"type":"code_execution_result","result":"1"},
        {"type":"code_execution_call","arguments":{"language":"python","code":"print(2)"},"id":"call-2"},
        {"type":"code_execution_result","result":"2"}
      ]
    }))
    code_interaction.code_execution_exchanges.size.should eq(2)
    code_interaction.code_execution_exchanges.find(&.call_id.nil?).not_nil!.outputs.should eq(["1"])
    code_interaction.code_execution_exchanges.find { |exchange| exchange.call_id == "call-2" }.not_nil!.code_snippets.should eq(["print(2)"])
  end

  it "reports interaction terminal and completed helpers" do
    interaction = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({"status":"completed","outputs":[]}))
    interaction.is_terminal.should be_true
    interaction.is_completed.should be_true

    failed = Crig::Providers::Gemini::Interactions::Interaction.from_json(%({"status":"failed","outputs":[]}))
    failed.is_terminal.should be_true
    failed.is_completed.should be_false
  end

  it "builds the interaction stream path" do
    Crig::Providers::Gemini::Interactions.build_interaction_stream_path("interaction-123").should eq(
      "/v1beta/interactions/interaction-123?stream=true"
    )
    Crig::Providers::Gemini::Interactions.build_interaction_stream_path("interaction-123", "event-456").should eq(
      "/v1beta/interactions/interaction-123?stream=true&last_event_id=event-456"
    )
  end

  it "adds inline citations from annotations" do
    text_content = Crig::Providers::Gemini::Interactions::TextContent.new(
      "Hello world",
      [
        Crig::Providers::Gemini::Interactions::Annotation.new(start_index: 6, end_index: 11, source: "https://example.com"),
        Crig::Providers::Gemini::Interactions::Annotation.new(start_index: 0, end_index: 5, source: "https://hello.example"),
      ]
    )

    text_content.with_inline_citations.should eq("Hello[1](https://hello.example) world[2](https://example.com)")

    interaction = Crig::Providers::Gemini::Interactions::Interaction.new(
      outputs: [Crig::Providers::Gemini::Interactions::Content.text(text_content)]
    )
    interaction.text_with_inline_citations.should eq("Hello[1](https://hello.example) world[2](https://example.com)")
  end

  it "parses typed agent config and tool choice config from additional params" do
    request = Crig::Completion::Request::CompletionRequestBuilder
      .from_prompt("Hello")
      .additional_params(
        JSON.parse(%({
          "agent_config":{"type":"deep-research","thinking_summaries":"auto"},
          "generation_config":{
            "tool_choice":{
              "allowed_tools":{
                "mode":"validated",
                "tools":["lookup"]
              }
            }
          }
        }))
      )
      .build

    result = Crig::Providers::Gemini::Interactions.create_request_body(
      "gemini-2.5-flash",
      request,
      false
    )

    result.agent_config.not_nil!.kind.deep_research?.should be_true
    result.agent_config.not_nil!.thinking_summaries.should eq(Crig::Providers::Gemini::Interactions::ThinkingSummaries::Auto)
    result.generation_config.not_nil!.tool_choice.not_nil!.kind.config?.should be_true
    result.generation_config.not_nil!.tool_choice.not_nil!.config.not_nil!.allowed_tools.mode.should eq(
      Crig::Providers::Gemini::Interactions::ToolChoiceType::Validated
    )
    result.generation_config.not_nil!.tool_choice.not_nil!.config.not_nil!.allowed_tools.tools.should eq(["lookup"])
  end

  it "serializes and deserializes extended interaction tool variants" do
    computer_use = Crig::Providers::Gemini::Interactions::Tool.computer_use(
      Crig::Providers::Gemini::Interactions::ComputerUseTool.new(
        environment: "browser",
        excluded_predefined_functions: ["shell"]
      )
    )
    mcp_server = Crig::Providers::Gemini::Interactions::Tool.mcp_server(
      Crig::Providers::Gemini::Interactions::McpServerTool.new(
        name: "github",
        url: "https://example.com/mcp",
        headers: JSON.parse(%({"Authorization":"Bearer token"})),
        allowed_tools: Crig::Providers::Gemini::Interactions::AllowedTools.new(
          mode: Crig::Providers::Gemini::Interactions::ToolChoiceType::Validated,
          tools: ["issues.list"]
        )
      )
    )
    file_search = Crig::Providers::Gemini::Interactions::Tool.file_search(
      Crig::Providers::Gemini::Interactions::FileSearchTool.new(
        file_search_store_names: ["kb"],
        top_k: 5_i64,
        metadata_filter: "kind = 'policy'"
      )
    )

    parsed_computer_use = Crig::Providers::Gemini::Interactions::Tool.from_json(computer_use.to_json)
    parsed_mcp_server = Crig::Providers::Gemini::Interactions::Tool.from_json(mcp_server.to_json)
    parsed_file_search = Crig::Providers::Gemini::Interactions::Tool.from_json(file_search.to_json)

    parsed_computer_use.kind.computer_use?.should be_true
    parsed_computer_use.computer_use.not_nil!.environment.should eq("browser")
    parsed_mcp_server.kind.mcp_server?.should be_true
    parsed_mcp_server.mcp_server.not_nil!.name.should eq("github")
    parsed_mcp_server.mcp_server.not_nil!.allowed_tools.not_nil!.tools.should eq(["issues.list"])
    parsed_file_search.kind.file_search?.should be_true
    parsed_file_search.file_search.not_nil!.file_search_store_names.should eq(["kb"])
    parsed_file_search.file_search.not_nil!.top_k.should eq(5_i64)
  end

  it "converts multimodal content and thought summary variants" do
    audio = Crig::Providers::Gemini::Interactions::Content.from_user_content(
      Crig::Completion::UserContent.audio("audiodata", Crig::Completion::AudioMediaType::MP3)
    )
    document = Crig::Providers::Gemini::Interactions::Content.from_user_content(
      Crig::Completion::UserContent.document("plain text document", Crig::Completion::DocumentMediaType::TXT)
    )
    video = Crig::Providers::Gemini::Interactions::Content.from_user_content(
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::Video,
        video: Crig::Completion::Video.new(
          Crig::Completion::DocumentSourceKind.url("https://example.com/video.mp4"),
          Crig::Completion::VideoMediaType::MP4
        )
      )
    )
    thought_summary = Crig::Providers::Gemini::Interactions::ThoughtSummaryContent.from_json(%({
      "data":"SGVsbG8=",
      "mime_type":"image/png",
      "resolution":"high"
    }))

    audio.kind.audio?.should be_true
    audio.audio.not_nil!.mime_type.should eq("audio/mp3")
    document.kind.document?.should be_true
    document.document.not_nil!.data.should eq("plain text document")
    video.kind.video?.should be_true
    video.video.not_nil!.uri.should eq("https://example.com/video.mp4")
    thought_summary.kind.image?.should be_true
    thought_summary.image.not_nil!.mime_type.should eq("image/png")
    thought_summary.image.not_nil!.resolution.should eq(Crig::Providers::Gemini::Interactions::MediaResolution::High)
  end
end

describe Crig::Providers::Gemini::Interactions::Streaming do
  it "maps text content delta events" do
    event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"content.delta",
      "index":0,
      "delta":{"type":"text","text":"Hello"}
    }))

    event.kind.content_delta?.should be_true
    choice = Crig::Providers::Gemini::Interactions::Streaming.content_delta_to_choice(event.delta.not_nil!)
    choice.not_nil!.kind.message?.should be_true
    choice.not_nil!.message.should eq("Hello")
  end

  it "maps function call content delta events" do
    event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"content.delta",
      "index":0,
      "delta":{"type":"function_call","name":"get_weather","arguments":{"location":"Paris"},"id":"call-1"}
    }))

    choice = Crig::Providers::Gemini::Interactions::Streaming.content_delta_to_choice(event.delta.not_nil!)
    choice.not_nil!.kind.tool_call?.should be_true
    choice.not_nil!.tool_call.not_nil!.name.should eq("get_weather")
    choice.not_nil!.tool_call.not_nil!.call_id.should eq("call-1")
  end

  it "parses raw interaction event streams" do
    events = Crig::Providers::Gemini::Interactions::Streaming.parse_event_stream(<<-SSE)
data: {"event_type":"content.start","index":0,"content":{"type":"text","text":"Hello"}}

data: {"event_type":"content.delta","index":0,"delta":{"type":"text","text":" world"}}

data: {"event_type":"interaction.complete","interaction":{"id":"interaction-1","outputs":[{"type":"text","text":"Hello world"}],"usage":{"total_input_tokens":1,"total_output_tokens":2,"total_tokens":3}}}

data: [DONE]
SSE

    events.size.should eq(3)
    events[0].kind.content_start?.should be_true
    events[1].kind.content_delta?.should be_true
    events[2].kind.interaction_complete?.should be_true
    events[2].interaction.not_nil!.id.should eq("interaction-1")
  end

  it "parses broader interaction event and delta variants" do
    status_event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"interaction.status_update",
      "interaction_id":"interaction-1",
      "status":"requires_action",
      "event_id":"event-1"
    }))
    stop_event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"content.stop",
      "index":2,
      "event_id":"event-2"
    }))
    error_event = Crig::Providers::Gemini::Interactions::Streaming::InteractionSseEvent.from_json(%({
      "event_type":"error",
      "error":{"code":"bad_request","message":"boom"},
      "event_id":"event-3"
    }))
    mcp_delta = Crig::Providers::Gemini::Interactions::Streaming::ContentDelta.from_json(%({
      "type":"mcp_server_tool_call",
      "name":"issues.list",
      "server_name":"github",
      "arguments":{"repo":"crig"},
      "id":"call-7"
    }))
    file_search_delta = Crig::Providers::Gemini::Interactions::Streaming::ContentDelta.from_json(%({
      "type":"file_search_result",
      "result":[{"title":"Policy","text":"Always test.","file_search_store":"kb"}]
    }))
    thought_summary_delta = Crig::Providers::Gemini::Interactions::Streaming::ContentDelta.from_json(%({
      "type":"thought_summary",
      "content":{"data":"SGVsbG8=","mime_type":"image/png"}
    }))

    status_event.kind.interaction_status_update?.should be_true
    status_event.interaction_id.should eq("interaction-1")
    status_event.status.not_nil!.kind.requires_action?.should be_true
    status_event.event_id.should eq("event-1")
    stop_event.kind.content_stop?.should be_true
    stop_event.index.should eq(2)
    error_event.kind.error?.should be_true
    error_event.error.not_nil!.message.should eq("boom")
    mcp_delta.kind.mcp_server_tool_call?.should be_true
    mcp_delta.mcp_server_tool_call.not_nil!.server_name.should eq("github")
    file_search_delta.kind.file_search_result?.should be_true
    file_search_delta.file_search_result.not_nil!.result.not_nil!.first.title.should eq("Policy")
    thought_summary_delta.kind.thought_summary?.should be_true
    Crig::Providers::Gemini::Interactions::Streaming.content_delta_to_choice(thought_summary_delta).should be_nil
  end
end

describe Crig::Providers::Gemini::Interactions::InteractionsCompletionModel do
  it "creates and fetches interactions through the client" do
    requests = [] of {String, String}
    http_server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      requests << {context.request.path, body}
      context.response.status_code = 200
      context.response.content_type = "application/json"

      case context.request.path
      when "/v1beta/interactions"
        context.response.print(%({"id":"interaction-create","outputs":[{"type":"text","text":"created"}]}))
      when "/v1beta/interactions/interaction-create"
        context.response.print(%({"id":"interaction-create","status":"completed","outputs":[{"type":"text","text":"fetched"}]}))
      else
        context.response.status_code = 404
        context.response.print(%({"message":"not found"}))
      end
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::InteractionsClient.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.completion_model("gemini-2.5-flash")
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Hello").build

    created = model.create_interaction(request)
    fetched = model.get_interaction("interaction-create")

    created.id.should eq("interaction-create")
    fetched.is_completed.should be_true
    requests[0][0].should eq("/v1beta/interactions")
    requests[1][0].should eq("/v1beta/interactions/interaction-create")

    http_server.close
  end

  it "streams interaction events from request and by id" do
    seen_paths = [] of String
    http_server = HTTP::Server.new do |context|
      seen_paths << context.request.resource
      context.response.status_code = 200
      context.response.content_type = "text/event-stream"
      context.response.print <<-SSE
data: {"event_type":"content.start","index":0,"content":{"type":"text","text":"Hello"}}

data: {"event_type":"content.delta","index":0,"delta":{"type":"function_call","name":"search","arguments":{"q":"rust"},"id":"call-1"}}

data: {"event_type":"interaction.complete","interaction":{"id":"interaction-1","outputs":[{"type":"text","text":"done"}],"usage":{"total_input_tokens":1,"total_output_tokens":2,"total_tokens":3}}}
SSE
    end
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Gemini::InteractionsClient.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.completion_model("gemini-2.5-flash")
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Hello").build

    request_events = model.stream_interaction_events(request)
    id_events = model.stream_interaction_events_by_id("interaction-1", "event-9")

    request_events.size.should eq(3)
    request_events[1].delta.not_nil!.kind.function_call?.should be_true
    id_events.last.interaction.not_nil!.id.should eq("interaction-1")
    seen_paths[0].should eq("/v1beta/interactions?alt=sse")
    seen_paths[1].should eq("/v1beta/interactions/interaction-1?stream=true&last_event_id=event-9&alt=sse")

    http_server.close
  end
end
