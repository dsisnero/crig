require "../../../spec_helper"
describe Crig::Providers::Anthropic::Client do
  it "supports anthropic client initialization and builder overrides" do
    client = Crig::Providers::Anthropic::Client.new("dummy-key")
    builder_client = Crig::Providers::Anthropic::Client.builder
      .api_key("dummy-key")
      .anthropic_version("2023-01-01")
      .anthropic_beta("prompt-caching-2024-07-31")
      .anthropic_beta("tools-2024-05-16")
      .build

    client.api_key.token.should eq("dummy-key")
    builder_client.api_key.token.should eq("dummy-key")
    builder_client.anthropic_version.should eq("2023-01-01")
    builder_client.anthropic_betas.should eq(["prompt-caching-2024-07-31", "tools-2024-05-16"])
  end

  it "ports ensures_client_builder_no_annotation" do
    http_client = HTTP::Client.new(URI.parse("http://127.0.0.1"))
    client = Crig::Providers::Anthropic::Client.builder
      .http_client(http_client)
      .api_key("Foo")
      .build

    client.http_client.as(HTTP::Client).should be(http_client)
    client.api_key.token.should eq("Foo")
  end

  it "accepts a custom HttpClientExt transport on the builder" do
    http_client = Crig::HttpClient::MockStreamingClient.new(Bytes["{}".bytes[0]])
    client = Crig::Providers::Anthropic::Client.builder
      .http_client(http_client)
      .api_key("Bar")
      .build

    client.http_client.should be_a(Crig::Providers::Anthropic::Client::WrappedTransport)
    client.api_key.token.should eq("Bar")
  end

  it "emits anthropic auth and version headers from the built client" do
    client = Crig::Providers::Anthropic::Client.builder
      .api_key("dummy-key")
      .anthropic_version("2023-01-01")
      .anthropic_betas(["prompt-caching-2024-07-31", "tools-2024-05-16"])
      .build

    headers = client.default_headers
    headers["x-api-key"].should eq("dummy-key")
    headers["anthropic-version"].should eq("2023-01-01")
    headers["anthropic-beta"].should eq("prompt-caching-2024-07-31,tools-2024-05-16")
  end
end

describe Crig::Providers::Anthropic::Message do
  it "deserializes anthropic assistant and user messages" do
    assistant_message = Crig::Providers::Anthropic::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":"\\n\\nHello there, how may I assist you today?"
    })))
    assistant_message2 = Crig::Providers::Anthropic::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":[
        {"type":"text","text":"\\n\\nHello there, how may I assist you today?"},
        {"type":"tool_use","id":"toolu_01A09q90qw90lq917835lq9","name":"get_weather","input":{"location":"San Francisco, CA"}}
      ]
    })))
    user_message = Crig::Providers::Anthropic::Message.from_json_value(JSON.parse(%({
      "role":"user",
      "content":[
        {"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"/9j/4AAQSkZJRg..."}},
        {"type":"text","text":"What is in this image?"},
        {"type":"tool_result","tool_use_id":"toolu_01A09q90qw90lq917835lq9","content":"15 degrees"}
      ]
    })))

    assistant_message.role.should eq(Crig::Providers::Anthropic::Role::Assistant)
    assistant_message.content.first.kind.text?.should be_true
    assistant_message.content.first.text.should eq("\n\nHello there, how may I assist you today?")

    assistant_message2.content.size.should eq(2)
    assistant_message2.content.first.kind.text?.should be_true
    assistant_message2.content.last.kind.tool_use?.should be_true
    assistant_message2.content.last.id.should eq("toolu_01A09q90qw90lq917835lq9")
    assistant_message2.content.last.name.should eq("get_weather")

    user_message.role.should eq(Crig::Providers::Anthropic::Role::User)
    user_message.content.size.should eq(3)
    user_message.content.first.kind.image?.should be_true
    user_message.content.to_a[1].kind.text?.should be_true
    user_message.content.last.kind.tool_result?.should be_true
  end

  it "round-trips between core messages and anthropic messages for supported content" do
    user_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::User,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::UserContent.text("hello"),
        Crig::Completion::UserContent.document("plain text document", Crig::Completion::DocumentMediaType::TXT),
      ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)),
    )
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.text("Hi there!"),
        Crig::Completion::AssistantContent.tool_call("tool_1", "lookup", JSON.parse(%({"city":"Paris"}))),
      ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)),
    )

    converted_user = Crig::Providers::Anthropic::Message.from_core_message(user_message)
    converted_assistant = Crig::Providers::Anthropic::Message.from_core_message(assistant_message)

    converted_user.role.should eq(Crig::Providers::Anthropic::Role::User)
    converted_user.content.size.should eq(2)
    converted_user.to_core_message.should eq(user_message)

    converted_assistant.role.should eq(Crig::Providers::Anthropic::Role::Assistant)
    converted_assistant.content.size.should eq(2)
    converted_assistant.to_core_message.should eq(assistant_message)
  end

  it "ports reasoning and document/cache-control helpers" do
    reasoning = Crig::Completion::Reasoning.new(
      [
        Crig::Completion::ReasoningContent.text("step", "sig_step"),
        Crig::Completion::ReasoningContent.summary("summary"),
        Crig::Completion::ReasoningContent.redacted("opaque-redacted"),
      ],
      "rs_1"
    )
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(Crig::Completion::AssistantContent::Kind::Reasoning, reasoning: reasoning)
      ),
    )

    anthropic_reasoning = Crig::Providers::Anthropic::Message.from_core_message(assistant_message)
    anthropic_reasoning.content.size.should eq(3)
    anthropic_reasoning.content.first.kind.thinking?.should be_true
    anthropic_reasoning.content.last.kind.redacted_thinking?.should be_true
    roundtripped_reasoning = anthropic_reasoning.to_core_message.content.to_a.map(&.as(Crig::Completion::AssistantContent))
    roundtripped_reasoning.size.should eq(3)
    roundtripped_reasoning[0].reasoning.not_nil!.content.size.should eq(1)
    roundtripped_reasoning[1].reasoning.not_nil!.content.first.text.should eq("summary")
    roundtripped_reasoning[2].reasoning.not_nil!.content.first.data.should eq("opaque-redacted")

    pdf = Crig::Providers::Anthropic::Content.document(
      Crig::Providers::Anthropic::DocumentSource.base64("JVBERi0xLjQ=", Crig::Providers::Anthropic::DocumentFormat::PDF)
    )
    pdf_json = Crig::Providers::OpenAI.build_json_any { |json| pdf.to_json(json) }
    pdf_json["source"]["media_type"].as_s.should eq("application/pdf")

    text_doc = Crig::Providers::Anthropic::Content.document(
      Crig::Providers::Anthropic::DocumentSource.text("hello world")
    )
    text_doc_json = Crig::Providers::OpenAI.build_json_any { |json| text_doc.to_json(json) }
    text_doc_json["source"]["media_type"].as_s.should eq("text/plain")

    system = [Crig::Providers::Anthropic::SystemContent.text("system prompt")]
    messages = [
      Crig::Providers::Anthropic::Message.new(
        Crig::Providers::Anthropic::Role::User,
        Crig::OneOrMany(Crig::Providers::Anthropic::Content).one(
          Crig::Providers::Anthropic::Content.text("hello")
        ),
      ),
    ]
    Crig::Providers::Anthropic.apply_cache_control(system, messages)
    system.last.cache_control.should eq(Crig::Providers::Anthropic::CacheControl.ephemeral)
    messages.last.content.last.cache_control.should eq(Crig::Providers::Anthropic::CacheControl.ephemeral)
  end
end

describe Crig::Providers::Anthropic::CompletionModel do
  it "ports tool choice and max token helpers" do
    Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.auto).kind.auto?.should be_true
    Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.none).kind.none?.should be_true
    Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.required).kind.any?.should be_true
    specific = Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.specific(["lookup_weather"]))
    specific.kind.tool?.should be_true
    specific.name.should eq("lookup_weather")

    expect_raises(Crig::Completion::CompletionError, "Only one tool may be specified to be used by Claude") do
      Crig::Providers::Anthropic::ToolChoice.from_core(Crig::Completion::ToolChoice.specific(["a", "b"]))
    end

    Crig::Providers::Anthropic.calculate_max_tokens(Crig::Providers::Anthropic::CLAUDE_4_SONNET).should eq(64_000_i64)
    Crig::Providers::Anthropic.calculate_max_tokens("claude-3-opus-20240229").should eq(4_096_i64)
    Crig::Providers::Anthropic.calculate_max_tokens("unknown-model").should be_nil
    Crig::Providers::Anthropic.calculate_max_tokens_custom("unknown-model").should eq(2_048_i64)

    client = Crig::Providers::Anthropic::Client.new("test-key")
    builder = Crig::Providers::Anthropic::CompletionModel.make(client, Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
      .completion_request("hello")
    builder.build.max_tokens.should eq(8_192_i64)

    explicit = Crig::Providers::Anthropic::CompletionModel.with_model(client, "custom-model")
      .completion_request("hello")
    explicit.build.max_tokens.should eq(2_048_i64)
  end

  it "sanitizes schemas and builds anthropic request payloads" do
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("What is 2+2?")
      .preamble("You are precise.")
      .max_tokens(64_i64)
      .tool(Crig::Completion::ToolDefinition.new("lookup_weather", "Find the weather", JSON.parse(%({"type":"object","properties":{"city":{"type":"string"}}}))))
      .tool_choice(Crig::Completion::ToolChoice.required)
      .output_schema(JSON.parse(%({
        "title":"math_response",
        "type":"object",
        "properties":{
          "value":{"type":"integer","minimum":1},
          "nested":{"type":"object","properties":{"name":{"type":"string"}}}
        }
      })))
      .additional_params(JSON.parse(%({"metadata":{"user_id":"user-123"}})))
      .build

    payload = Crig::Providers::Anthropic::AnthropicCompletionRequest.from_params(
      Crig::Providers::Anthropic::AnthropicRequestParams.new(
        Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
        request,
        true,
      ),
    ).to_json_value

    payload["model"].as_s.should eq(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
    payload["max_tokens"].as_i64.should eq(64_i64)
    payload["system"].as_a.last["cache_control"]["type"].as_s.should eq("ephemeral")
    payload["messages"].as_a.last["content"].as_a.last["text"].as_s.should eq("What is 2+2?")
    payload["messages"].as_a.last["content"].as_a.last["cache_control"]["type"].as_s.should eq("ephemeral")
    payload["tool_choice"]["type"].as_s.should eq("any")
    payload["tools"].as_a.first["name"].as_s.should eq("lookup_weather")
    payload["tools"].as_a.first["input_schema"]["properties"]["city"]["type"].as_s.should eq("string")
    payload["output_config"]["format"]["schema"]["additionalProperties"].as_bool.should be_false
    payload["output_config"]["format"]["schema"]["required"].as_a.map(&.as_s).sort.should eq(["nested", "value"])
    payload["output_config"]["format"]["schema"]["properties"]["value"]["minimum"]?.should be_nil
    payload["output_config"]["format"]["schema"]["properties"]["nested"]["additionalProperties"].as_bool.should be_false
    payload["metadata"]["user_id"].as_s.should eq("user-123")
  end

  it "posts anthropic completion requests and parses responses" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.content_type = "application/json"
      context.response.print(%({
        "id":"msg_123",
        "type":"message",
        "role":"assistant",
        "model":"claude-3-5-sonnet-latest",
        "content":[{"type":"text","text":"Anthropic answer"}],
        "stop_reason":"end_turn",
        "stop_sequence":null,
        "usage":{"input_tokens":10,"output_tokens":4}
      }))
    end
    begin
      address = http_server.bind_tcp("127.0.0.1", 0)
    rescue ex : Socket::BindError
      ex.to_s.should contain("Operation not permitted")
      http_server.close
      next
    end
    spawn { http_server.listen }

    client = Crig::Providers::Anthropic::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
      .completion(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    response.choice.first.text.not_nil!.text.should eq("Anthropic answer")
    response.usage.input_tokens.should eq(10_i64)
    response.usage.output_tokens.should eq(4_i64)
    response.raw_response.as(Crig::Providers::Anthropic::CompletionResponse).id.should eq("msg_123")
    requests.first["messages"].as_a.first["content"].as_s.should eq("hello")
    requests.first["max_tokens"].as_i64.should eq(8_192_i64)

    http_server.close
  end
end

describe Crig::Providers::Anthropic::StreamingEvent do
  it "ports anthropic streaming delta deserialization tests" do
    thinking_delta = Crig::Providers::Anthropic::ContentDelta.from_json_value(
      JSON.parse(%({"type":"thinking_delta","thinking":"Let me think about this..."}))
    )
    thinking_delta.kind.thinking_delta?.should be_true
    thinking_delta.thinking.should eq("Let me think about this...")

    signature_delta = Crig::Providers::Anthropic::ContentDelta.from_json_value(
      JSON.parse(%({"type":"signature_delta","signature":"abc123def456"}))
    )
    signature_delta.kind.signature_delta?.should be_true
    signature_delta.signature.should eq("abc123def456")

    thinking_event = Crig::Providers::Anthropic::StreamingEvent.from_json_value(
      JSON.parse(%({
        "type":"content_block_delta",
        "index":0,
        "delta":{"type":"thinking_delta","thinking":"First, I need to understand the problem."}
      }))
    )
    thinking_event.kind.content_block_delta?.should be_true
    thinking_event.index.should eq(0)
    thinking_event.delta.not_nil!.kind.thinking_delta?.should be_true

    signature_event = Crig::Providers::Anthropic::StreamingEvent.from_json_value(
      JSON.parse(%({
        "type":"content_block_delta",
        "index":0,
        "delta":{"type":"signature_delta","signature":"ErUBCkYICBgCIkCaGbqC85F4"}
      }))
    )
    signature_event.kind.content_block_delta?.should be_true
    signature_event.delta.not_nil!.kind.signature_delta?.should be_true
    signature_event.delta.not_nil!.signature.should eq("ErUBCkYICBgCIkCaGbqC85F4")
  end
end

describe Crig::Providers::Anthropic do
  it "ports anthropic streaming event handling tests" do
    tool_call_state = nil.as(Crig::Providers::Anthropic::ToolCallState?)
    thinking_state = nil.as(Crig::Providers::Anthropic::ThinkingState?)

    event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
      delta: Crig::Providers::Anthropic::ContentDelta.new(
        Crig::Providers::Anthropic::ContentDeltaKind::ThinkingDelta,
        thinking: "Analyzing the request..."
      ),
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(event, tool_call_state, thinking_state)
    choice.not_nil!.kind.reasoning_delta?.should be_true
    choice.not_nil!.reasoning_delta.should eq("Analyzing the request...")
    thinking_state.not_nil!.thinking.should eq("Analyzing the request...")

    event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
      delta: Crig::Providers::Anthropic::ContentDelta.new(
        Crig::Providers::Anthropic::ContentDeltaKind::SignatureDelta,
        signature: "test_signature"
      ),
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(event, tool_call_state, thinking_state)
    choice.should be_nil
    thinking_state.not_nil!.signature.should eq("test_signature")

    redacted_event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockStart,
      index: 0,
      content_block: Crig::Providers::Anthropic::Content.redacted_thinking("redacted_blob"),
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(redacted_event, tool_call_state, thinking_state)
    choice.not_nil!.kind.reasoning?.should be_true
    choice.not_nil!.reasoning_content.not_nil!.data.should eq("redacted_blob")

    text_event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
      delta: Crig::Providers::Anthropic::ContentDelta.new(
        Crig::Providers::Anthropic::ContentDeltaKind::TextDelta,
        text: "Hello, world!"
      ),
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(text_event, nil, nil)
    choice.not_nil!.kind.message?.should be_true
    choice.not_nil!.message.should eq("Hello, world!")

    active_tool = Crig::Providers::Anthropic::ToolCallState.new("test_tool", "tool_123", "internal_123", "")
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(event, active_tool, nil)
    choice.should be_nil
    thinking_state.not_nil!.signature.should eq("test_signature")
    tool_call_state.not_nil!.id.should eq("tool_123")

    json_event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
      delta: Crig::Providers::Anthropic::ContentDelta.new(
        Crig::Providers::Anthropic::ContentDeltaKind::InputJsonDelta,
        partial_json: "{\"arg\":\"value"
      ),
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(json_event, active_tool, nil)
    choice.not_nil!.kind.tool_call_delta?.should be_true
    choice.not_nil!.id.should eq("tool_123")
    choice.not_nil!.content.not_nil!.kind.delta?.should be_true
    choice.not_nil!.content.not_nil!.value.should eq("{\"arg\":\"value")
    tool_call_state.not_nil!.input_json.should eq("{\"arg\":\"value")

    tool_call_state = Crig::Providers::Anthropic::ToolCallState.new("test_tool", "tool_123", "internal_123", "")
    [
      "{\"location\":",
      "\"Paris\",",
      "\"temp\":\"20C\"}",
    ].each do |delta|
      event = Crig::Providers::Anthropic::StreamingEvent.new(
        Crig::Providers::Anthropic::StreamingEventKind::ContentBlockDelta,
        delta: Crig::Providers::Anthropic::ContentDelta.new(
          Crig::Providers::Anthropic::ContentDeltaKind::InputJsonDelta,
          partial_json: delta
        ),
        index: 0,
      )
      choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(event, tool_call_state, thinking_state)
      choice.should_not be_nil
    end
    tool_call_state.not_nil!.input_json.should eq("{\"location\":\"Paris\",\"temp\":\"20C\"}")

    stop_event = Crig::Providers::Anthropic::StreamingEvent.new(
      Crig::Providers::Anthropic::StreamingEventKind::ContentBlockStop,
      index: 0,
    )
    choice, tool_call_state, thinking_state = Crig::Providers::Anthropic.handle_event(stop_event, tool_call_state, thinking_state)
    choice.not_nil!.kind.tool_call?.should be_true
    choice.not_nil!.tool_call.not_nil!.id.should eq("tool_123")
    choice.not_nil!.tool_call.not_nil!.name.should eq("test_tool")
    choice.not_nil!.tool_call.not_nil!.arguments["location"].as_s.should eq("Paris")
    choice.not_nil!.tool_call.not_nil!.arguments["temp"].as_s.should eq("20C")
    tool_call_state.should be_nil
  end

  it "parses anthropic streaming responses with reasoning and tool calls" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.content_type = "text/event-stream"
      context.response.print <<-SSE
data: {"type":"message_start","message":{"id":"msg_stream_1","role":"assistant","content":[],"model":"claude-3-5-sonnet-latest","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":7,"output_tokens":0}}}

data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":null}}

data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Analyzing..."}}

data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig123"}}

data: {"type":"content_block_stop","index":0}

data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool_123","name":"lookup_weather","input":{}}}

data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"city\\":\\"Paris\\"}"}}

data: {"type":"content_block_stop","index":1}

data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Final answer"}}

data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":5}}

data: {"type":"message_stop"}

SSE
    end

    begin
      address = http_server.bind_tcp("127.0.0.1", 0)
    rescue ex : Socket::BindError
      ex.to_s.should contain("Operation not permitted")
      http_server.close
      next
    end
    spawn { http_server.listen }

    client = Crig::Providers::Anthropic::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Anthropic::CLAUDE_3_5_SONNET)
      .stream(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    items = [] of Crig::StreamedAssistantContent(Crig::Providers::Anthropic::StreamingCompletionResponse)
    response.each_item { |item| items << item }

    items[0].kind.reasoning_delta?.should be_true
    items[0].reasoning_delta.should eq("Analyzing...")
    items[1].kind.reasoning?.should be_true
    items[1].reasoning.not_nil!.content.first.signature.should eq("sig123")
    items[2].kind.tool_call_delta?.should be_true
    items[2].content.not_nil!.kind.name?.should be_true
    items[3].kind.tool_call_delta?.should be_true
    items[3].content.not_nil!.kind.delta?.should be_true
    items[4].kind.tool_call?.should be_true
    items[4].tool_call.not_nil!.function.arguments["city"].as_s.should eq("Paris")
    items[5].kind.text?.should be_true
    items[5].text.not_nil!.text.should eq("Final answer")
    items.last.kind.final?.should be_true
    items.last.final.not_nil!.usage.output_tokens.should eq(5_i64)
    response.message_id.should eq("msg_stream_1")
    requests.first["stream"].as_bool.should be_true

    http_server.close
  end
end

describe Crig::Providers::Anthropic::DocumentSource do
  it "serializes file_id document source" do
    source = Crig::Providers::Anthropic::DocumentSource.file("file_abc")
    json = JSON.parse(source.to_json)
    json["type"].should eq("file")
    json["file_id"].should eq("file_abc")
  end

  it "deserializes file_id document source" do
    json = JSON.parse(%({"type":"file","file_id":"file_abc"}))
    source = Crig::Providers::Anthropic::DocumentSource.from_json_value(json)
    source.kind.file?.should be_true
    source.file_id.should eq("file_abc")
  end

  it "converts rig file_id document to anthropic file content" do
    rig_doc = Crig::Completion::UserContent.document_file_id("file_abc")
    anthropic_content = Crig::Providers::Anthropic::Message.content_from_user(rig_doc)
    anthropic_content.kind.document?.should be_true
    source = anthropic_content.source.as(Crig::Providers::Anthropic::DocumentSource)
    source.kind.file?.should be_true
    source.file_id.should eq("file_abc")
  end

  it "converts anthropic file content to rig file_id document" do
    anthropic_content = Crig::Providers::Anthropic::Content.document(
      Crig::Providers::Anthropic::DocumentSource.file("file_abc")
    )
    rig_content = Crig::Providers::Anthropic::Message.user_content_to_core(anthropic_content)
    rig_content.kind.document?.should be_true
    rig_content.document.not_nil!.data.kind.file_id?.should be_true
    rig_content.document.not_nil!.data.try_into_inner.should eq("file_abc")
  end
end

describe Crig::Providers::Anthropic do
  it "matches max tokens for current anthropic models" do
    Crig::Providers::Anthropic.calculate_max_tokens(Crig::Providers::Anthropic::CLAUDE_OPUS_4_7).should eq(128_000_i64)
    Crig::Providers::Anthropic.calculate_max_tokens(Crig::Providers::Anthropic::CLAUDE_OPUS_4_6).should eq(128_000_i64)
    Crig::Providers::Anthropic.calculate_max_tokens(Crig::Providers::Anthropic::CLAUDE_SONNET_4_6).should eq(64_000_i64)
    Crig::Providers::Anthropic.calculate_max_tokens(Crig::Providers::Anthropic::CLAUDE_HAIKU_4_5).should eq(64_000_i64)
  end

  it "uses conservative default max tokens fallback for unknown models" do
    Crig::Providers::Anthropic.calculate_max_tokens("claude-unknown").should be_nil
    Crig::Providers::Anthropic.calculate_max_tokens_custom("claude-unknown").should eq(2_048_i64)
  end
  it "normalizes empty end_turn response to empty text choice" do
    response = Crig::Providers::Anthropic::CompletionResponse.new(
      id: "msg_123",
      model: Crig::Providers::Anthropic::CLAUDE_SONNET_4_6,
      role: "assistant",
      stop_reason: "end_turn",
      content: [] of Crig::Providers::Anthropic::Content,
      usage: Crig::Providers::Anthropic::Usage.new(input_tokens: 7, output_tokens: 2),
    )
    parsed = response.to_crig_response
    parsed.choice.len.should eq(1)
    first = parsed.choice.first
    first.kind.text?.should be_true
  end

  it "errors on empty non-end_turn response" do
    response = Crig::Providers::Anthropic::CompletionResponse.new(
      id: "msg_123",
      model: Crig::Providers::Anthropic::CLAUDE_SONNET_4_6,
      role: "assistant",
      stop_reason: "tool_use",
      content: [] of Crig::Providers::Anthropic::Content,
      usage: Crig::Providers::Anthropic::Usage.new(input_tokens: 7, output_tokens: 2),
    )
    expect_raises(Crig::Completion::CompletionError, /Response contained no message/) do
      response.to_crig_response
    end
  end
end
