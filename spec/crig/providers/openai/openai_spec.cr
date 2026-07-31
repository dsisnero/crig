require "../../../spec_helper"
describe Crig::Providers::OpenAI do
  it "adds additionalProperties false to object schemas" do
    schema = JSON.parse(%({
      "type":"object",
      "properties":{
        "name":{"type":"string"}
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    sanitized["additionalProperties"].as_bool.should be_false
  end

  it "marks all object properties as required" do
    schema = JSON.parse(%({
      "type":"object",
      "properties":{
        "a":{"type":"string"},
        "b":{"type":"number"}
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    sanitized["required"].as_a.map(&.as_s).sort.should eq(["a", "b"])
  end

  it "sanitizes refs, required properties, and additionalProperties like upstream" do
    schema = JSON.parse(%({
      "type": "object",
      "properties": {
        "location": {
          "$ref": "#/$defs/Location",
          "description": "The user's location"
        }
      },
      "$defs": {
        "Location": {
          "type": "object",
          "properties": {
            "city": { "type": "string" },
            "state": { "type": "string" }
          }
        }
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    sanitized["properties"]["location"].to_json.should eq(%({"$ref":"#/$defs/Location"}))
    sanitized["$defs"]["Location"]["additionalProperties"].should eq(JSON::Any.new(false))
    sanitized["$defs"]["Location"]["required"].as_a.map(&.as_s).should eq(["city", "state"])
  end

  it "converts oneOf to anyOf recursively" do
    schema = JSON.parse(%({
      "type": "object",
      "properties": {
        "value": {
          "oneOf": [
            {"type":"string"},
            {"type":"number"}
          ]
        }
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    sanitized["properties"]["value"]["oneOf"]?.should be_nil
    sanitized["properties"]["value"]["anyOf"].as_a.size.should eq(2)
  end

  it "recurses into nested object schemas" do
    schema = JSON.parse(%({
      "type":"object",
      "properties":{
        "inner":{
          "type":"object",
          "properties":{
            "value":{"type":"string"}
          }
        }
      }
    }))

    sanitized = Crig::Providers::OpenAI.sanitize_schema(schema)

    inner = sanitized["properties"]["inner"]
    inner["additionalProperties"].as_bool.should be_false
    inner["required"].as_a.map(&.as_s).should eq(["value"])
  end
end

describe Crig::Providers::OpenAI::Client do
  it "builds from env and preserves base_url when converting to completions_api" do
    previous_key = ENV["OPENAI_API_KEY"]?
    previous_base = ENV["OPENAI_BASE_URL"]?

    ENV["OPENAI_API_KEY"] = "env-key"
    ENV["OPENAI_BASE_URL"] = "http://127.0.0.1:9999/v1"

    client = Crig::Providers::OpenAI::Client.from_env
    completions = client.completions_api

    client.api_key.token.should eq("env-key")
    client.base_url.should eq("http://127.0.0.1:9999/v1")
    completions.api_key.token.should eq("env-key")
    completions.base_url.should eq("http://127.0.0.1:9999/v1")
  ensure
    if previous_key
      ENV["OPENAI_API_KEY"] = previous_key
    else
      ENV.delete("OPENAI_API_KEY")
    end

    if previous_base
      ENV["OPENAI_BASE_URL"] = previous_base
    else
      ENV.delete("OPENAI_BASE_URL")
    end
  end

  it "posts Responses API requests through the default completion model" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"resp_1",
          "object":"response",
          "created_at":1,
          "status":"completed",
          "model":"gpt-4o",
          "usage":{
            "input_tokens":2,
            "input_tokens_details":{"cached_tokens":0},
            "output_tokens":1,
            "output_tokens_details":{"reasoning_tokens":0},
            "total_tokens":3
          },
          "output":[
            {
              "type":"message",
              "id":"msg_1",
              "role":"assistant",
              "status":"completed",
              "content":[{"type":"output_text","text":"default client answer"}]
            }
          ],
          "tools":[]
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build
    )

    response.choice.first.text.not_nil!.text.should eq("default client answer")
    server.requests.first["input"].as_a.first["type"].as_s.should eq("message")

    http_server.close
  end

  it "parses Responses API streaming chunks into reasoning, tool call deltas, and final usage" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "text/event-stream",
        body:         <<-SSE,
data: {"type":"response.output_item.added","item_id":"fc_1","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"sum","arguments":{},"status":"in_progress"},"sequence_number":1}

data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":0,"content_index":0,"sequence_number":2,"delta":"{\\"a\\":2"}

data: {"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":0,"content_index":0,"sequence_number":3,"delta":",\\"b\\":5}"}

data: {"type":"response.reasoning_summary_text.delta","output_index":1,"summary_index":0,"sequence_number":4,"delta":"thinking"}

data: {"type":"response.output_item.done","item_id":"rs_1","output_index":1,"item":{"type":"reasoning","id":"rs_1","summary":[{"type":"summary_text","text":"step 1"}],"encrypted_content":"enc_blob","status":"completed"},"sequence_number":5}

data: {"type":"response.output_item.done","item_id":"fc_1","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"sum","arguments":{"a":2,"b":5},"status":"completed"},"sequence_number":6}

data: {"type":"response.output_text.delta","output_index":2,"content_index":0,"sequence_number":7,"delta":"7"}

data: {"type":"response.completed","response":{"id":"resp_stream","object":"response","created_at":1,"status":"completed","model":"gpt-4o","usage":{"input_tokens":3,"input_tokens_details":{"cached_tokens":0},"output_tokens":4,"output_tokens_details":{"reasoning_tokens":1},"total_tokens":7},"output":[],"tools":[]},"sequence_number":8}

SSE
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.completion_model(Crig::Providers::OpenAI::GPT_4O).stream(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("What is 2+5?").build
    )

    items = [] of Crig::StreamedAssistantContent(Crig::Providers::OpenAI::ResponsesStreamingCompletionResponse)
    response.each_item { |item| items << item }

    items.count(&.kind.tool_call_delta?).should eq(3)
    items.any? { |item| item.kind.reasoning_delta? && item.reasoning_delta == "thinking" }.should be_true
    items.any? { |item| item.kind.reasoning? && item.reasoning.not_nil!.content.first.summary == "step 1" }.should be_true
    items.any? { |item| item.kind.reasoning? && item.reasoning.not_nil!.encrypted_content == "enc_blob" }.should be_true
    items.any? { |item| item.kind.tool_call? && item.tool_call.not_nil!.function.name == "sum" }.should be_true
    items.any? { |item| item.kind.text? && item.text.not_nil!.text == "7" }.should be_true
    items.last.final.not_nil!.usage.total_tokens.should eq(7)

    http_server.close
  end

  it "auto-adds reasoning encrypted include when reasoning params are present" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"resp_reasoning_include",
          "object":"response",
          "created_at":1,
          "status":"completed",
          "model":"gpt-4o",
          "usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2},
          "output":[
            {
              "type":"message",
              "id":"msg_reasoning_include",
              "role":"assistant",
              "status":"completed",
              "content":[{"type":"output_text","text":"ok"}]
            }
          ],
          "tools":[]
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello")
      .additional_params(JSON.parse(%({"reasoning":{"effort":"low"}})))
      .build

    client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)

    request_body = server.requests.first
    request_body["include"].as_a.map(&.as_s).should contain("reasoning.encrypted_content")

    http_server.close
  end

  it "returns an error without panicking for invalid responses additional_params payloads" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello")
      .additional_params(JSON.parse("true"))
      .build

    expect_raises(Crig::Completion::CompletionError, /Invalid OpenAI Responses additional_params payload/) do
      client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)
    end
  end

  it "returns an error without panicking when request reasoning content is missing an OpenAI id" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: Crig::Completion::Reasoning.new("thought"),
        )
      ),
      "assistant_message_id",
    )
    request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(assistant_message),
    )

    # Reasoning without ID is now skipped (matches upstream behavior)
    # The request has no valid items, so it errors with "must contain at least one item"
    expect_raises(Crig::Completion::CompletionError, /must contain at least one item/) do
      client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)
    end
  end
end

describe Crig::Providers::OpenAI::ResponsesCompletionModel do
  it "supports the class-level with_model helper" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    model = Crig::Providers::OpenAI::ResponsesCompletionModel.with_model(client, "gpt-test")

    model.client.should eq(client)
    model.model.should eq("gpt-test")
  end

  it "emits summary then encrypted reasoning items from a completed reasoning output" do
    model = Crig::Providers::OpenAI::ResponsesCompletionModel.new(
      Crig::Providers::OpenAI::Client.new("test-key"),
      Crig::Providers::OpenAI::GPT_4O,
    )

    summary = [
      Crig::Providers::OpenAI::ReasoningSummary.new("step 1"),
      Crig::Providers::OpenAI::ReasoningSummary.new("step 2"),
    ]

    choices = model.reasoning_choices_from_done_item("rs_1", summary, "enc_blob")

    choices.size.should eq(3)
    choices[0].reasoning_id.should eq("rs_1")
    choices[0].reasoning_content.not_nil!.summary.should eq("step 1")
    choices[1].reasoning_content.not_nil!.summary.should eq("step 2")
    choices[2].reasoning_content.not_nil!.data.should eq("enc_blob")
  end

  it "emits summary-only reasoning items when encrypted content is absent" do
    model = Crig::Providers::OpenAI::ResponsesCompletionModel.new(
      Crig::Providers::OpenAI::Client.new("test-key"),
      Crig::Providers::OpenAI::GPT_4O,
    )

    summary = [Crig::Providers::OpenAI::ReasoningSummary.new("only summary")]
    choices = model.reasoning_choices_from_done_item("rs_2", summary, nil)

    choices.size.should eq(1)
    choices[0].reasoning_id.should eq("rs_2")
    choices[0].reasoning_content.not_nil!.summary.should eq("only summary")
  end

  it "deserializes response chunk kinds from wire values" do
    chunk = Crig::Providers::OpenAI::ResponseChunk.from_json(%({
      "type":"response.completed",
      "response":{
        "id":"resp_1",
        "object":"response",
        "created_at":1,
        "status":"completed",
        "model":"gpt-4o",
        "usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3},
        "output":[],
        "tools":[]
      },
      "sequence_number":9
    }))

    chunk.kind.should eq(Crig::Providers::OpenAI::ResponseChunkKind::ResponseCompleted)
    chunk.response.id.should eq("resp_1")
    chunk.sequence_number.should eq(9)
  end

  it "deserializes output item chunks into typed payload wrappers" do
    chunk = Crig::Providers::OpenAI::ItemChunk.from_json(%({
      "type":"response.output_item.done",
      "item_id":"fc_1",
      "output_index":0,
      "item":{
        "type":"function_call",
        "id":"fc_1",
        "call_id":"call_1",
        "name":"sum",
        "arguments":{"a":2,"b":5},
        "status":"completed"
      },
      "sequence_number":6
    }))

    chunk.item_id.should eq("fc_1")
    chunk.output_index.should eq(0)
    chunk.data.should be_a(Crig::Providers::OpenAI::OutputItemDone)
    output_item = chunk.data.as(Crig::Providers::OpenAI::OutputItemDone)
    output_item.message.item.kind.should eq(Crig::Providers::OpenAI::Output::Kind::FunctionCall)
    output_item.message.item.function_call.not_nil!.name.should eq("sum")
  end

  it "deserializes reasoning summary text deltas into typed chunks" do
    chunk = Crig::Providers::OpenAI::ItemChunk.from_json(%({
      "type":"response.reasoning_summary_text.delta",
      "output_index":0,
      "summary_index":0,
      "sequence_number":4,
      "delta":"thinking"
    }))

    chunk.data.should be_a(Crig::Providers::OpenAI::ReasoningSummaryTextDelta)
    chunk.data.as(Crig::Providers::OpenAI::ReasoningSummaryTextDelta).chunk.delta.should eq("thinking")
  end

  it "deserializes content part chunks into typed part variants" do
    chunk = Crig::Providers::OpenAI::ContentPartChunk.from_json(%({
      "content_index":0,
      "sequence_number":3,
      "part":{"type":"output_text","text":"hello"}
    }))

    chunk.part.kind.should eq(Crig::Providers::OpenAI::ContentPartChunkPart::Kind::OutputText)
    chunk.part.text.should eq("hello")
  end

  it "deserializes summary part chunks into typed part variants" do
    chunk = Crig::Providers::OpenAI::SummaryPartChunk.from_json(%({
      "summary_index":1,
      "sequence_number":7,
      "part":{"type":"summary_text","text":"step 1"}
    }))

    chunk.part.kind.should eq(Crig::Providers::OpenAI::SummaryPartChunkPart::Kind::SummaryText)
    chunk.part.text.should eq("step 1")
  end
end

describe Crig::Providers::OpenAI::Reasoning do
  it "builds reasoning helper values like upstream" do
    reasoning = Crig::Providers::OpenAI::Reasoning.new
      .with_effort(Crig::Providers::OpenAI::ReasoningEffort::High)
      .with_summary_level(Crig::Providers::OpenAI::ReasoningSummaryLevel::Detailed)

    reasoning.effort.should eq(Crig::Providers::OpenAI::ReasoningEffort::High)
    reasoning.summary.should eq(Crig::Providers::OpenAI::ReasoningSummaryLevel::Detailed)
    reasoning.to_json_value["effort"].as_s.should eq("high")
    reasoning.to_json_value["summary"].as_s.should eq("detailed")
  end
end

describe Crig::Providers::OpenAI::AdditionalParameters do
  it "ensures reasoning requests include encrypted reasoning content" do
    params = Crig::Providers::OpenAI::AdditionalParameters.from_json_value(
      JSON.parse(%({
        "reasoning":{"effort":"high"}
      }))
    ).ensure_reasoning_include

    include_values = params.to_json_value["include"].as_a.map(&.as_s)
    include_values.should eq(["reasoning.encrypted_content"])
  end

  it "parses typed additional parameter enums from OpenAI wire values" do
    params = Crig::Providers::OpenAI::AdditionalParameters.from_json_value(
      JSON.parse(%({
        "truncation":"auto",
        "service_tier":"flex",
        "reasoning":{"effort":"high","summary":"detailed"}
      }))
    )

    params.truncation.should eq(Crig::Providers::OpenAI::TruncationStrategy::Auto)
    params.service_tier.should eq(Crig::Providers::OpenAI::OpenAIServiceTier::Flex)
    params.reasoning.not_nil!.effort.should eq(Crig::Providers::OpenAI::ReasoningEffort::High)
    params.reasoning.not_nil!.summary.should eq(Crig::Providers::OpenAI::ReasoningSummaryLevel::Detailed)
  end

  it "keeps structured outputs in typed text config" do
    params = Crig::Providers::OpenAI::AdditionalParameters.new.with_text(
      Crig::Providers::OpenAI::TextConfig.structured_output(
        "response_schema",
        JSON.parse(%({"type":"object","properties":{"answer":{"type":"string"}}}))
      )
    )

    text = params.to_json_value["text"]["format"]
    text["type"].as_s.should eq("json_schema")
    text["name"].as_s.should eq("response_schema")
  end
end

describe Crig::Providers::OpenAI::TextFormat do
  it "serializes the plain text format variant" do
    json = Crig::Providers::OpenAI::TextFormat.text.to_json_value

    json["type"].as_s.should eq("text")
  end

  it "serializes the json_schema format variant" do
    json = Crig::Providers::OpenAI::TextFormat.structured_output(
      "response_schema",
      JSON.parse(%({"type":"object","properties":{"answer":{"type":"string"}}}))
    ).to_json_value

    json["type"].as_s.should eq("json_schema")
    json["name"].as_s.should eq("response_schema")
    json["schema"]["properties"]["answer"]["type"].as_s.should eq("string")
  end
end

describe Crig::Providers::OpenAI::CompletionRequest do
  it "applies structured outputs and reasoning through typed helper methods" do
    request = Crig::Providers::OpenAI::CompletionRequest.new(
      input: Crig::OneOrMany(Crig::Providers::OpenAI::InputItem).one(
        Crig::Providers::OpenAI::InputItem.system_message("Be precise.")
      ),
      model: Crig::Providers::OpenAI::GPT_4O,
    )
      .with_structured_outputs(
        "response_schema",
        JSON.parse(%({"type":"object","properties":{"answer":{"type":"string"}}}))
      )
      .with_reasoning(
        Crig::Providers::OpenAI::Reasoning.new
          .with_effort(Crig::Providers::OpenAI::ReasoningEffort::High)
      )

    json = request.to_json_value
    json["model"].as_s.should eq(Crig::Providers::OpenAI::GPT_4O)
    json["text"]["format"]["name"].as_s.should eq("response_schema")
    json["reasoning"]["effort"].as_s.should eq("high")
  end
end

describe Crig::Providers::OpenAI::Message do
  it "builds system messages with input_text content" do
    message = Crig::Providers::OpenAI::Message.system("Be precise.")
    json = message.to_json_value

    json["role"].as_s.should eq("system")
    json["content"].as_a.first["type"].as_s.should eq("input_text")
    json["content"].as_a.first["text"].as_s.should eq("Be precise.")
  end

  it "converts mixed user tool-result content into tool-result messages only" do
    tool_result = Crig::Completion::ToolResult.new(
      "tool_result_id",
      Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
        Crig::Completion::ToolResultContent.text("done")
      ),
      call_id: "call_1",
    )
    contents = [
      Crig::Completion::UserContent.text("ignored"),
      Crig::Completion::UserContent.new(
        Crig::Completion::UserContent::Kind::ToolResult,
        tool_result: tool_result,
      ),
    ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::User,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many(contents)
    )

    converted = Crig::Providers::OpenAI::Message.from_core_message(message)

    converted.size.should eq(1)
    converted.first.kind.tool_result?.should be_true
    converted.first.to_json_value["type"].as_s.should eq("tool")
    converted.first.to_json_value["tool_call_id"].as_s.should eq("call_1")
    converted.first.to_json_value["output"].as_s.should eq("done")
  end

  it "converts assistant reasoning into an assistant message with reasoning content" do
    reasoning = Crig::Completion::Reasoning.new("thought").with_id("rs_1")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    converted = Crig::Providers::OpenAI::Message.from_core_message(message)

    converted.size.should eq(1)
    converted.first.kind.assistant?.should be_true
    converted.first.to_json_value["content"].as_a.first["type"].as_s.should eq("reasoning")
    converted.first.to_json_value["content"].as_a.first["id"].as_s.should eq("rs_1")
  end

  it "parses developer-role message JSON as a system message" do
    message = Crig::Providers::OpenAI::Message.from_json_value(
      JSON.parse(%({
        "type":"message",
        "role":"developer",
        "content":[{"type":"input_text","text":"Be strict."}]
      }))
    )

    message.kind.system?.should be_true
    message.to_json_value["role"].as_s.should eq("system")
    message.to_json_value["content"].as_a.first["text"].as_s.should eq("Be strict.")
  end

  it "parses string content for system and user messages like upstream" do
    system_message = Crig::Providers::OpenAI::Message.from_json_value(
      JSON.parse(%({
        "type":"message",
        "role":"system",
        "content":"Be strict."
      }))
    )
    user_message = Crig::Providers::OpenAI::Message.from_json_value(
      JSON.parse(%({
        "type":"message",
        "role":"user",
        "content":"hello"
      }))
    )

    system_message.to_json_value["content"].as_a.first["text"].as_s.should eq("Be strict.")
    user_message.to_json_value["content"].as_a.first["text"].as_s.should eq("hello")
  end
end

describe Crig::Providers::OpenAI::SystemContent do
  it "builds input_text content from strings" do
    content = Crig::Providers::OpenAI::SystemContent.from_string("Be precise.")

    content.to_json_value["type"].as_s.should eq("input_text")
    content.to_json_value["text"].as_s.should eq("Be precise.")
  end
end

describe Crig::Providers::OpenAI::InputItem do
  it "serializes system_message with the merged role" do
    json = Crig::Providers::OpenAI::InputItem.system_message("Stay strict.").to_json_value

    json["role"].as_s.should eq("system")
    json["content"].as_a.first["text"].as_s.should eq("Stay strict.")
  end

  it "serializes a user message input item without duplicating the role field" do
    item = Crig::Providers::OpenAI::InputItem.new(
      Crig::Providers::OpenAI::InputContent.message(
        Crig::Providers::OpenAI::Message.user([
          Crig::Providers::OpenAI::UserContent.text("hello"),
        ])
      ),
      Crig::Providers::OpenAI::Role::User,
    )

    json = item.to_json_value.to_json
    json.scan(/"role"/).size.should eq(1)
  end

  it "does not duplicate the assistant role when converting typed assistant reasoning messages" do
    item = Crig::Providers::OpenAI::InputItem.from_message(
      Crig::Providers::OpenAI::Message.assistant([
        Crig::Providers::OpenAI::AssistantContentType.reasoning(
          Crig::Providers::OpenAI::OpenAIReasoning.new("rs_1", [] of Crig::Providers::OpenAI::ReasoningSummary)
        ),
      ], "assistant_message_id")
    )

    json = item.to_json_value
    json["type"].as_s.should eq("message")
    json["role"].as_s.should eq("assistant")
    json.to_json.scan(/"role"/).size.should eq(1)
    json["content"].as_a.first["type"].as_s.should eq("reasoning")
  end

  it "converts tool-result messages into function_call_output items without roles" do
    item = Crig::Providers::OpenAI::InputItem.from_message(
      Crig::Providers::OpenAI::Message.tool_result("call_1", "done")
    )

    json = item.to_json_value
    json["type"].as_s.should eq("function_call_output")
    json["call_id"].as_s.should eq("call_1")
    json["output"].as_s.should eq("done")
    json["role"]?.should be_nil
  end

  it "parses raw tool payloads through the message-to-input-item path" do
    item = Crig::Providers::OpenAI::InputItem.from_json_value(
      JSON.parse(%({
        "type":"tool",
        "tool_call_id":"call_2",
        "output":"ok"
      }))
    )

    json = item.to_json_value
    json["type"].as_s.should eq("function_call_output")
    json["call_id"].as_s.should eq("call_2")
    json["output"].as_s.should eq("ok")
  end

  it "skips assistant reasoning when missing an OpenAI reasoning id" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: Crig::Completion::Reasoning.new("thought"),
        )
      ),
      "assistant_message_id",
    )

    items = Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    items.should be_empty
  end

  it "serializes encrypted-only reasoning content without adding summaries" do
    reasoning = Crig::Completion::Reasoning.new([Crig::Completion::ReasoningContent.encrypted("encrypted_blob")], "rs_1")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    items = Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    json = items.first.to_json_value

    json["type"].as_s.should eq("reasoning")
    json["id"].as_s.should eq("rs_1")
    json["encrypted_content"].as_s.should eq("encrypted_blob")
    json["summary"].as_a.size.should eq(0)
  end

  it "serializes mixed reasoning content using only text-like summaries and first opaque payload" do
    reasoning = Crig::Completion::Reasoning.new([
      Crig::Completion::ReasoningContent.text("step-1", "sig-1"),
      Crig::Completion::ReasoningContent.summary("summary-2"),
      Crig::Completion::ReasoningContent.encrypted("ciphertext"),
      Crig::Completion::ReasoningContent.redacted("redacted"),
    ], "rs_2")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    items = Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    json = items.first.to_json_value

    json["summary"].as_a.map { |entry| entry["text"].as_s }.should eq(["step-1", "summary-2"])
    json["encrypted_content"].as_s.should eq("ciphertext")
  end

  it "serializes redacted-only reasoning as encrypted content" do
    reasoning = Crig::Completion::Reasoning.new([
      Crig::Completion::ReasoningContent.redacted("opaque-redacted"),
    ], "rs_redacted")
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    items = Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    json = items.first.to_json_value
    json["encrypted_content"].as_s.should eq("opaque-redacted")
    json["summary"].as_a.size.should eq(0)
  end

  it "requires tool result call ids when converting user tool results" do
    tool_result = Crig::Completion::ToolResult.new(
      "tool_result_id",
      Crig::OneOrMany(Crig::Completion::ToolResultContent).one(
        Crig::Completion::ToolResultContent.text("done")
      ),
    )
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::User,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::ToolResult,
          tool_result: tool_result,
        )
      ),
    )

    expect_raises(Crig::Completion::CompletionError, /Tool result `call_id` is required/) do
      Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    end
  end

  it "requires assistant tool call call ids when converting assistant tool calls" do
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.tool_call(
          "tool_1",
          "my_tool",
          JSON.parse(%({"arg":"value"}))
        )
      ),
      "assistant_message_id",
    )

    expect_raises(Crig::Completion::CompletionError, /Assistant tool call `call_id` is required/) do
      Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    end
  end

  it "roundtrips empty reasoning content into a request item without dropping it" do
    output = Crig::Providers::OpenAI::Output.from_json_value(
      JSON.parse(%({
        "type":"reasoning",
        "id":"rs_roundtrip_empty",
        "summary":[]
      }))
    )

    reasoning = output.to_assistant_content.first.reasoning.not_nil!
    message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )

    items = Crig::Providers::OpenAI::InputItem.from_completion_message(message)
    json = items.first.to_json_value

    json["id"].as_s.should eq("rs_roundtrip_empty")
    json["summary"].as_a.size.should eq(0)
    json["encrypted_content"]?.should be_nil
  end
end

describe Crig::Providers::OpenAI::OpenAIReasoning do
  it "serializes reasoning summaries and encrypted content" do
    reasoning = Crig::Providers::OpenAI::OpenAIReasoning.new(
      "rs_1",
      [Crig::Providers::OpenAI::ReasoningSummary.new("step 1")],
      "enc_blob",
    )

    json = reasoning.to_json_value
    json["type"].as_s.should eq("reasoning")
    json["id"].as_s.should eq("rs_1")
    json["summary"].as_a.first["text"].as_s.should eq("step 1")
    json["encrypted_content"].as_s.should eq("enc_blob")
  end
end

describe Crig::Providers::OpenAI::AssistantContent do
  it "converts output_text and refusal into core assistant text content" do
    Crig::Providers::OpenAI::AssistantContent.output_text("hello").to_completion_content.text.not_nil!.text.should eq("hello")
    Crig::Providers::OpenAI::AssistantContent.refusal("no").to_completion_content.text.not_nil!.text.should eq("no")
  end
end

describe Crig::Providers::OpenAI::CompletionResponsePayload do
  it "parses typed response metadata and preserves additional parameters" do
    payload = Crig::Providers::OpenAI::CompletionResponsePayload.from_json(%({
      "id":"resp_1",
      "object":"response",
      "created_at":1,
      "status":"completed",
      "model":"gpt-4o",
      "output":[],
      "tools":[],
      "usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3},
      "service_tier":"flex"
    }))

    payload.object.should eq(Crig::Providers::OpenAI::ResponseObject::Response)
    payload.status.should eq(Crig::Providers::OpenAI::ResponseStatus::Completed)
    payload.usage.not_nil!.total_tokens.should eq(3)
    payload.additional_parameters["service_tier"].as_s.should eq("flex")
  end

  it "converts typed output into a core completion response" do
    payload = Crig::Providers::OpenAI::CompletionResponsePayload.from_json(%({
      "id":"resp_2",
      "object":"response",
      "created_at":2,
      "status":"completed",
      "model":"gpt-4o",
      "output":[
        {
          "type":"message",
          "id":"msg_2",
          "role":"assistant",
          "status":"completed",
          "content":[{"type":"output_text","text":"hello"}]
        }
      ],
      "tools":[],
      "usage":{"input_tokens":2,"output_tokens":3,"total_tokens":5}
    }))

    response = payload.to_completion_response
    response.message_id.should eq("msg_2")
    response.choice.to_a.first.text.not_nil!.text.should eq("hello")
    response.usage.total_tokens.should eq(5)
  end
end

describe Crig::Providers::OpenAI::Output do
  it "converts typed message output into assistant text and preserves message id" do
    output = Crig::Providers::OpenAI::Output.from_json_value(
      JSON.parse(%({
        "type":"message",
        "id":"msg_1",
        "role":"assistant",
        "status":"completed",
        "content":[{"type":"output_text","text":"hello"}]
      }))
    )

    output.message_id.should eq("msg_1")
    output.to_assistant_content.map(&.text.not_nil!.text).should eq(["hello"])
  end

  it "converts typed reasoning output into core reasoning content" do
    output = Crig::Providers::OpenAI::Output.from_json_value(
      JSON.parse(%({
        "type":"reasoning",
        "id":"rs_1",
        "summary":[{"type":"summary_text","text":"step 1"}],
        "encrypted_content":"enc_blob"
      }))
    )

    reasoning = output.to_assistant_content.first.reasoning.not_nil!
    reasoning.id.should eq("rs_1")
    reasoning.content.first.summary.should eq("step 1")
    reasoning.content.last.data.should eq("enc_blob")
  end

  it "does not drop reasoning output when the summary is empty" do
    output = Crig::Providers::OpenAI::Output.from_json_value(
      JSON.parse(%({
        "type":"reasoning",
        "id":"rs_empty",
        "summary":[]
      }))
    )

    content = output.to_assistant_content
    content.size.should eq(1)
    reasoning = content.first.reasoning.not_nil!
    reasoning.id.should eq("rs_empty")
    reasoning.content.should be_empty
  end
end

describe Crig::Providers::OpenAI::OutputReasoning do
  it "converts typed output reasoning into core reasoning content" do
    output = Crig::Providers::OpenAI::OutputReasoning.new(
      "rs_2",
      [Crig::Providers::OpenAI::ReasoningSummary.new("step 2")],
      "enc_2",
      Crig::Providers::OpenAI::ToolStatus::Completed,
    )

    reasoning = output.to_completion_content.reasoning.not_nil!
    reasoning.id.should eq("rs_2")
    reasoning.content.first.summary.should eq("step 2")
    reasoning.content.last.data.should eq("enc_2")
  end
end

describe Crig::Providers::OpenAI::ResponsesToolDefinition do
  it "sanitizes and serializes tool definitions through the typed wrapper" do
    tool = Crig::Completion::ToolDefinition.new(
      "lookup_weather",
      "Look up weather by city",
      JSON.parse(%({
        "type":"object",
        "properties":{"city":{"type":"string"}}
      })),
    )

    response_tool = Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool_definition(tool)

    response_tool.kind.should eq("function")
    response_tool.strict?.should be_true
    response_tool.to_json_value["parameters"]["additionalProperties"].as_bool.should be_false
  end

  it "sanitizes nested object schemas recursively" do
    all_object_schemas_strict = uninitialized Proc(JSON::Any, Bool)
    all_object_schemas_strict = ->(value : JSON::Any) do
      if object = value.as_h?
        if object["type"]?.try(&.as_s?) == "object" && object["additionalProperties"]?.try(&.as_bool?) != false
          false
        else
          object.each_value.all? { |entry| all_object_schemas_strict.call(entry) }
        end
      elsif array = value.as_a?
        array.all? { |entry| all_object_schemas_strict.call(entry) }
      else
        true
      end
    end

    tool = Crig::Completion::ToolDefinition.new(
      "submit",
      "Submit",
      JSON.parse(%({
        "type":"object",
        "properties":{
          "first_name":{"type":"string"},
          "last_name":{"type":"string"},
          "job":{
            "type":"object",
            "properties":{
              "inner":{"type":"string"},
              "department":{
                "type":"object",
                "properties":{
                  "name":{"type":"string"}
                }
              }
            }
          }
        }
      })),
    )

    response_tool = Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool_definition(tool)

    all_object_schemas_strict.call(response_tool.parameters).should be_true
  end

  it "sanitizes array item object schemas recursively" do
    all_object_schemas_strict = uninitialized Proc(JSON::Any, Bool)
    all_object_schemas_strict = ->(value : JSON::Any) do
      if object = value.as_h?
        if object["type"]?.try(&.as_s?) == "object" && object["additionalProperties"]?.try(&.as_bool?) != false
          false
        else
          object.each_value.all? { |entry| all_object_schemas_strict.call(entry) }
        end
      elsif array = value.as_a?
        array.all? { |entry| all_object_schemas_strict.call(entry) }
      else
        true
      end
    end

    tool = Crig::Completion::ToolDefinition.new(
      "submit",
      "Submit",
      JSON.parse(%({
        "type":"object",
        "properties":{
          "employees":{
            "type":"array",
            "items":{
              "type":"object",
              "properties":{
                "name":{"type":"string"},
                "role":{"type":"string"}
              }
            }
          }
        }
      })),
    )

    response_tool = Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool_definition(tool)

    all_object_schemas_strict.call(response_tool.parameters).should be_true
  end

  it "sanitizes enum-like anyOf schemas recursively" do
    all_object_schemas_strict = uninitialized Proc(JSON::Any, Bool)
    all_object_schemas_strict = ->(value : JSON::Any) do
      if object = value.as_h?
        if object["type"]?.try(&.as_s?) == "object" && object["additionalProperties"]?.try(&.as_bool?) != false
          false
        else
          object.each_value.all? { |entry| all_object_schemas_strict.call(entry) }
        end
      elsif array = value.as_a?
        array.all? { |entry| all_object_schemas_strict.call(entry) }
      else
        true
      end
    end

    tool = Crig::Completion::ToolDefinition.new(
      "submit",
      "Submit",
      JSON.parse(%({
        "type":"object",
        "properties":{
          "name":{"type":"string"},
          "pricing":{
            "anyOf":[
              {
                "type":"object",
                "properties":{"fixed":{"type":"boolean"}}
              },
              {
                "type":"object",
                "properties":{"tiered":{"type":"boolean"}}
              }
            ]
          }
        }
      })),
    )

    response_tool = Crig::Providers::OpenAI::ResponsesToolDefinition.from_tool_definition(tool)

    all_object_schemas_strict.call(response_tool.parameters).should be_true
  end
end

describe Crig::Providers::OpenAI::ToolStatus do
  it "serializes all currently tracked OpenAI tool statuses" do
    Crig::Providers::OpenAI::ToolStatus::InProgress.to_wire.should eq("in_progress")
    Crig::Providers::OpenAI::ToolStatus::Completed.to_wire.should eq("completed")
    Crig::Providers::OpenAI::ToolStatus::Incomplete.to_wire.should eq("incomplete")
  end
end

describe Crig::Providers::OpenAI::ToolResultContentType do
  it "exposes the text wire value" do
    Crig::Providers::OpenAI::ToolResultContentType::Text.to_wire.should eq("text")
  end
end

describe Crig::Providers::OpenAI::UserContent do
  it "serializes the tool result variant with the tool wire type" do
    json = Crig::Providers::OpenAI::UserContent.tool_result("call_1", "done").to_json_value

    json["type"].as_s.should eq("tool")
    json["tool_call_id"].as_s.should eq("call_1")
    json["output"].as_s.should eq("done")
  end
end

describe Crig::Providers::OpenAI::UserContent do
  it "serializes image and file payloads with OpenAI wire keys" do
    image = Crig::Providers::OpenAI::UserContent.image("https://example.com/cat.png", "high")
    file = Crig::Providers::OpenAI::UserContent.file(file_url: "https://example.com/doc.pdf", filename: "doc.pdf")

    image.to_json_value["type"].as_s.should eq("input_image")
    image.to_json_value["image_url"].as_s.should eq("https://example.com/cat.png")
    image.to_json_value["detail"].as_s.should eq("high")

    file.to_json_value["type"].as_s.should eq("input_file")
    file.to_json_value["file_url"].as_s.should eq("https://example.com/doc.pdf")
    file.to_json_value["filename"].as_s.should eq("doc.pdf")
  end
end

describe Crig::Providers::OpenAI::AssistantContentType do
  it "serializes text assistant content through the typed wrapper" do
    content = Crig::Providers::OpenAI::AssistantContentType.text(
      Crig::Providers::OpenAI::AssistantContent.output_text("done")
    )

    json = content.to_json_value
    json["type"].as_s.should eq("output_text")
    json["text"].as_s.should eq("done")
  end
end

describe Crig::Providers::OpenAI::CompletionsClient do
  it "supports the rust-shaped chat completion helper layer" do
    core_tool = Crig::Completion::ToolDefinition.new(
      "lookup",
      "Look up a value",
      JSON.parse(%({"type":"object","properties":{"query":{"type":"string"}}}))
    )
    request = Crig::Providers::OpenAI::Chat::CompletionRequest.from_openai_request_params(
      Crig::Providers::OpenAI::Chat::OpenAIRequestParams.new(
        Crig::Providers::OpenAI::GPT_4O,
        Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello")
          .tool(core_tool)
          .build,
        strict_tools: true,
        tool_result_array_content: true,
      )
    )

    request.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    request.messages.first.kind.system?.should be_false
    request.messages.first.kind.user?.should be_true
    request.tools.first.function.strict?.should eq(true)
    request.tools.first.function.parameters["additionalProperties"].as_bool.should be_false
  end

  it "converts typed chat completion responses into core completion responses" do
    response = Crig::Providers::OpenAI::Chat::CompletionResponse.from_json_value(JSON.parse(%({
      "id":"chatcmpl-typed",
      "object":"chat.completion",
      "created":1,
      "model":"gpt-4o",
      "choices":[
        {
          "index":0,
          "message":{
            "role":"assistant",
            "content":[{"type":"text","text":"typed answer"}],
            "tool_calls":[]
          },
          "logprobs":null,
          "finish_reason":"stop"
        }
      ],
      "usage":{"prompt_tokens":2,"total_tokens":5}
    })))

    converted = response.to_completion_response(JSON.parse(response.to_json))

    converted.choice.first.text.not_nil!.text.should eq("typed answer")
    converted.usage.total_tokens.should eq(5)
    converted.message_id.should eq("chatcmpl-typed")
  end

  it "supports completion model class and builder helpers" do
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    model = Crig::Providers::OpenAI::CompletionModel.with_model(client, Crig::Providers::OpenAI::GPT_4O)
      .with_tool_result_array_content
      .with_strict_tools

    model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    model.tool_result_array_content?.should be_true
    model.strict_tools?.should be_true
    model.into_agent_builder.build.should be_a(Crig::Agent(Crig::Providers::OpenAI::CompletionModel))
  end

  it "posts chat completions requests and respects request model overrides and max_tokens" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"chatcmpl-final",
          "object":"chat.completion",
          "created":1,
          "model":"gpt-4o-mini",
          "choices":[
            {
              "index":0,
              "message":{"role":"assistant","content":"final answer","tool_calls":[]},
              "logprobs":null,
              "finish_reason":"stop"
            }
          ],
          "usage":{"prompt_tokens":2,"total_tokens":5}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.completion_model(Crig::Providers::OpenAI::GPT_4O)
    request = model
      .completion_request("What is 2+5?")
      .model(Crig::Providers::OpenAI::GPT_4O_MINI)
      .preamble("system prompt")
      .max_tokens(42)
      .build

    response = model.completion(request)

    response.choice.first.text.not_nil!.text.should eq("final answer")
    response.usage.total_tokens.should eq(5)

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::GPT_4O_MINI)
    posted["max_tokens"].as_i64.should eq(42)
    posted["messages"].as_a.first["role"].as_s.should eq("system")
    posted["messages"].as_a.last["content"].as_s.should eq("What is 2+5?")

    http_server.close
  end

  it "uses the model default when the request override is unset and omits max_tokens when none" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"chatcmpl-default-model",
          "object":"chat.completion",
          "created":1,
          "model":"gpt-4o",
          "choices":[
            {
              "index":0,
              "message":{"role":"assistant","content":"ok","tool_calls":[]},
              "logprobs":null,
              "finish_reason":"stop"
            }
          ],
          "usage":{"prompt_tokens":1,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.completion_model(Crig::Providers::OpenAI::GPT_4O)
    request = model.completion_request("Hello").build

    model.completion(request)

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::GPT_4O)
    posted["max_tokens"]?.should be_nil

    http_server.close
  end

  it "skips assistant reasoning while preserving assistant text and tool calls" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"chatcmpl-reasoning-filter",
          "object":"chat.completion",
          "created":1,
          "model":"gpt-4o",
          "choices":[
            {
              "index":0,
              "message":{"role":"assistant","content":"ok","tool_calls":[]},
              "logprobs":null,
              "finish_reason":"stop"
            }
          ],
          "usage":{"prompt_tokens":1,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    reasoning = Crig::Completion::Reasoning.new("think").with_id("rs_1")
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        ),
        Crig::Completion::AssistantContent.text("visible text"),
        Crig::Completion::AssistantContent.tool_call("tool_1", "subtract", JSON.parse(%({"x":2,"y":5}))),
      ] of (Crig::Completion::UserContent | Crig::Completion::AssistantContent)),
      "assistant_message_id",
    )

    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(assistant_message),
      model: Crig::Providers::OpenAI::GPT_4O,
    )

    client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)

    posted = server.requests.first["messages"].as_a.first
    posted["role"].as_s.should eq("assistant")
    posted["content"].as_a.map { |entry| entry["text"].as_s }.should eq(["visible text"])
    posted["tool_calls"].as_a.size.should eq(1)
    posted["tool_calls"].as_a.first["function"]["name"].as_s.should eq("subtract")

    http_server.close
  end

  it "errors when all chat completion messages are filtered out during conversion" do
    reasoning = Crig::Completion::Reasoning.new("think").with_id("rs_1")
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.new(
          Crig::Completion::AssistantContent::Kind::Reasoning,
          reasoning: reasoning,
        )
      ),
      "assistant_message_id",
    )
    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key")
    request = Crig::Completion::Request::CompletionRequest.new(
      chat_history: Crig::OneOrMany(Crig::Completion::Message).one(assistant_message),
      model: Crig::Providers::OpenAI::GPT_4O,
    )

    expect_raises(Crig::Completion::CompletionError, /no provider-compatible messages after conversion/) do
      client.completion_model(Crig::Providers::OpenAI::GPT_4O).completion(request)
    end
  end

  it "parses streaming text and tool call deltas into the generic streaming response" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "text/event-stream",
        body:         <<-SSE,
data: {"id":"chatcmpl-stream","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"sum","arguments":"a"}}]}}]}

data: {"id":"chatcmpl-stream","choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"b"}}]}}],"usage":{"prompt_tokens":3,"total_tokens":7}}

data: {"id":"chatcmpl-stream","choices":[{"delta":{"content":"7"}}]}

data: [DONE]

SSE
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::CompletionsClient.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.completion_model(Crig::Providers::OpenAI::GPT_4O).stream(
      Crig::Completion::Request::CompletionRequestBuilder.from_prompt("What is 2+5?").build
    )

    items = [] of Crig::StreamedAssistantContent(Crig::Client::FinalCompletionResponse)
    response.each_item { |item| items << item }

    items.select(&.kind.tool_call_delta?).size.should eq(3)
    items.any? { |item| item.kind.tool_call? && item.tool_call.not_nil!.function.name == "sum" }.should be_true
    items.any? { |item| item.kind.text? && item.text.not_nil!.text == "7" }.should be_true
    items.last.kind.final?.should be_true
    response.message_id.should eq("chatcmpl-stream")

    http_server.close
  end
end

describe Crig::Providers::OpenAI::Client do
  it "deserializes typed openai chat messages" do
    assistant_message = Crig::Providers::OpenAI::Chat::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":"\\n\\nHello there, how may I assist you today?"
    })))
    assistant_message2 = Crig::Providers::OpenAI::Chat::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "content":[{"type":"text","text":"\\n\\nHello there, how may I assist you today?"}],
      "tool_calls":null
    })))
    assistant_message3 = Crig::Providers::OpenAI::Chat::Message.from_json_value(JSON.parse(%({
      "role":"assistant",
      "tool_calls":[{"id":"call_h89ipqYUjEpCPI6SxspMnoUU","type":"function","function":{"name":"subtract","arguments":"{\\"x\\": 2, \\"y\\": 5}"}}],
      "content":null,
      "refusal":null
    })))
    user_message = Crig::Providers::OpenAI::Chat::Message.from_json_value(JSON.parse(%({
      "role":"user",
      "content":[
        {"type":"text","text":"What's in this image?"},
        {"type":"image_url","image_url":{"url":"https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"}},
        {"type":"input_audio","input_audio":{"data":"...","format":"mp3"}}
      ]
    })))

    assistant_message.assistant_content.first.text.should eq("\n\nHello there, how may I assist you today?")
    assistant_message2.assistant_content.first.text.should eq("\n\nHello there, how may I assist you today?")
    assistant_message2.tool_calls.should eq([] of Crig::Providers::OpenAI::Chat::ToolCall)
    assistant_message3.assistant_content.should eq([] of Crig::Providers::OpenAI::Chat::AssistantContent)
    assistant_message3.tool_calls.first.function.name.should eq("subtract")
    assistant_message3.tool_calls.first.function.arguments.should eq(JSON.parse(%({"x":2,"y":5})))
    user_message.user_content.not_nil!.first.text.should eq("What's in this image?")
    user_message.user_content.not_nil!.to_a[1].image_url.not_nil!.url.should contain("Gfp-wisconsin-madison")
  end

  it "round-trips between core messages and openai chat messages" do
    user_message = Crig::Completion::Message.user("Hello")
    assistant_message = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.text("Hi there!")
      )
    )

    converted_user_message = Crig::Providers::OpenAI::Chat::Message.from_core_message(user_message)
    converted_assistant_message = Crig::Providers::OpenAI::Chat::Message.from_core_message(assistant_message)

    converted_user_message.first.user_content.not_nil!.first.text.should eq("Hello")
    converted_assistant_message.first.assistant_content.first.text.should eq("Hi there!")

    converted_user_message.first.to_core_message.should eq(user_message)
    converted_assistant_message.first.to_core_message.should eq(assistant_message)
  end

  it "serializes single-text user messages as strings" do
    user_message = Crig::Providers::OpenAI::Chat::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenAI::Chat::UserContent).one(
        Crig::Providers::OpenAI::Chat::UserContent.text("Hello world")
      )
    )

    serialized = user_message.to_json_value

    serialized["role"].as_s.should eq("user")
    serialized["content"].as_s.should eq("Hello world")
  end

  it "serializes multi-part and single-image user messages as arrays" do
    multi_part = Crig::Providers::OpenAI::Chat::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenAI::Chat::UserContent).many([
        Crig::Providers::OpenAI::Chat::UserContent.text("What's in this image?"),
        Crig::Providers::OpenAI::Chat::UserContent.image("https://example.com/image.jpg"),
      ])
    )
    single_image = Crig::Providers::OpenAI::Chat::Message.user(
      Crig::OneOrMany(Crig::Providers::OpenAI::Chat::UserContent).one(
        Crig::Providers::OpenAI::Chat::UserContent.image("https://example.com/image.jpg")
      )
    )

    multi_part.to_json_value["content"].as_a.size.should eq(2)
    single_image.to_json_value["content"].as_a.size.should eq(1)
  end

  it "supports openai client builders" do
    client = Crig::Providers::OpenAI::Client.builder
      .api_key("dummy-key")
      .base_url("https://example.com/v1")
      .build
    completions_client = Crig::Providers::OpenAI::CompletionsClient.builder
      .api_key("dummy-key")
      .base_url("https://example.com/v1")
      .build

    client.base_url.should eq("https://example.com/v1")
    completions_client.base_url.should eq("https://example.com/v1")
  end
end

describe Crig::Providers::OpenAI::EmbeddingModel do
  it "posts embedding requests and maps returned vectors back to documents" do
    server = FakeOpenAIEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[
            {"object":"embedding","embedding":[0.1,0.2],"index":0},
            {"object":"embedding","embedding":[0.3,0.4],"index":1}
          ],
          "model":"text-embedding-3-small",
          "usage":{"prompt_tokens":2,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.embedding_model(Crig::Providers::OpenAI::TEXT_EMBEDDING_3_SMALL)
    embeddings = model.embed_texts(["alpha", "beta"])

    embeddings.map(&.document).should eq(["alpha", "beta"])
    embeddings.map(&.vec).should eq([[0.1, 0.2], [0.3, 0.4]])
    model.ndims.should eq(1536)

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::TEXT_EMBEDDING_3_SMALL)
    posted["input"].as_a.map(&.as_s).should eq(["alpha", "beta"])
    posted["dimensions"].as_i.should eq(1536)

    http_server.close
  end

  it "supports explicit ndims, encoding format, and user request fields" do
    server = FakeOpenAIEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[1.0],"index":0}],
          "model":"custom-embed",
          "usage":{"prompt_tokens":1,"total_tokens":1}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = Crig::Providers::OpenAI::EmbeddingModel
      .with_encoding_format(client, "custom-embed", 256, Crig::Providers::OpenAI::EncodingFormat::Float)
      .user("user_123")

    model.embed_text("hello").vec.should eq([1.0])

    posted = server.requests.first
    posted["dimensions"].as_i.should eq(256)
    posted["encoding_format"].as_s.should eq("float")
    posted["user"].as_s.should eq("user_123")

    http_server.close
  end

  it "omits dimensions for text-embedding-ada-002 and validates response length" do
    server = FakeOpenAIEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[0.1],"index":0}],
          "model":"text-embedding-ada-002",
          "usage":{"prompt_tokens":2,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.embedding_model(Crig::Providers::OpenAI::TEXT_EMBEDDING_ADA_002)

    expect_raises(Crig::Embeddings::EmbeddingError, /does not match input length/) do
      model.embed_texts(["one", "two"])
    end

    posted = server.requests.first
    posted["dimensions"]?.should be_nil

    http_server.close
  end
end

describe Crig::Providers::OpenAI::ImageGenerationModel do
  it "posts image generation requests and decodes the returned base64 image" do
    encoded = Base64.strict_encode("png-bytes")
    server = FakeOpenAIImageGenerationServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({"created":1,"data":[{"b64_json":"#{encoded}"}]}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.image_generation_model(Crig::Providers::OpenAI::DALL_E_3)
      .image_generation(Crig::ImageGenerationRequest.new("A cat", 1024, 1024))

    String.new(response.image).should eq("png-bytes")
    response.response.created.should eq(1)

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::DALL_E_3)
    posted["prompt"].as_s.should eq("A cat")
    posted["size"].as_s.should eq("1024x1024")
    posted["response_format"].as_s.should eq("b64_json")

    http_server.close
  end

  it "omits response_format for gpt-image-1 and merges additional params" do
    encoded = Base64.strict_encode("img")
    server = FakeOpenAIImageGenerationServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({"created":1,"data":[{"b64_json":"#{encoded}"}]}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    request = client.image_generation_model(Crig::Providers::OpenAI::GPT_IMAGE_1)
      .image_generation_request
      .prompt("A tree")
      .width(512)
      .height(768)
      .additional_params(JSON.parse(%({"quality":"high"})))
      .build

    client.image_generation_model(Crig::Providers::OpenAI::GPT_IMAGE_1).image_generation(request)

    posted = server.requests.first
    posted["response_format"]?.should be_nil
    posted["quality"].as_s.should eq("high")
    posted["size"].as_s.should eq("512x768")

    http_server.close
  end

  it "surfaces provider errors for non-success responses" do
    server = FakeOpenAIImageGenerationServer.new do |_request|
      {
        content_type: "application/json",
        body:         "invalid request",
        status_code:  400,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")

    expect_raises(Crig::ImageGenerationError, /BAD_REQUEST: invalid request/) do
      client.image_generation_model(Crig::Providers::OpenAI::DALL_E_2)
        .image_generation(Crig::ImageGenerationRequest.new("A dog", 256, 256))
    end

    http_server.close
  end
end

describe Crig::Providers::OpenAI::TranscriptionModel do
  it "posts multipart transcription requests and parses the returned text" do
    server = FakeOpenAITranscriptionServer.new do |_parts|
      {
        content_type: "application/json",
        body:         %({"text":"hello world"}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.transcription_model(Crig::Providers::OpenAI::WHISPER_1)
      .transcription(Crig::TranscriptionRequest.new("abc".to_slice, "speech.wav", "en", "hint", 0.2))

    response.text.should eq("hello world")
    model_part = server.parts.find { |part| part[:name] == "model" }.not_nil!
    file_part = server.parts.find { |part| part[:name] == "file" }.not_nil!
    language_part = server.parts.find { |part| part[:name] == "language" }.not_nil!
    prompt_part = server.parts.find { |part| part[:name] == "prompt" }.not_nil!
    temperature_part = server.parts.find { |part| part[:name] == "temperature" }.not_nil!

    model_part[:body].should eq(Crig::Providers::OpenAI::WHISPER_1)
    file_part[:body].should eq("abc")
    file_part[:filename].should eq("speech.wav")
    language_part[:body].should eq("en")
    prompt_part[:body].should eq("hint")
    temperature_part[:body].should eq("0.2")

    http_server.close
  end

  it "forwards additional transcription params and surfaces provider errors" do
    server = FakeOpenAITranscriptionServer.new do |_parts|
      {
        content_type: "application/json",
        body:         %({"error":{"message":"bad transcription"}}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")

    expect_raises(Crig::TranscriptionError, /bad transcription/) do
      client.transcription_model(Crig::Providers::OpenAI::WHISPER_1)
        .transcription(
          Crig::TranscriptionRequest.new(
            "abc".to_slice,
            "speech.wav",
            additional_params: JSON.parse(%({"temperature_fallback":"0.4"}))
          )
        )
    end

    additional_part = server.parts.find { |part| part[:name] == "temperature_fallback" }.not_nil!
    additional_part[:body].should eq("0.4")

    http_server.close
  end
end

describe Crig::Providers::OpenAI::AudioGenerationModel do
  it "posts audio generation requests and returns binary audio bytes" do
    server = FakeOpenAIAudioGenerationServer.new do |_request|
      {
        content_type: "application/octet-stream",
        body:         "audio-bytes",
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    response = client.audio_generation_model(Crig::Providers::OpenAI::TTS_1)
      .audio_generation(Crig::AudioGenerationRequest.new("hello", "alloy", 1.25_f32))

    String.new(response.audio).should eq("audio-bytes")
    String.new(response.response).should eq("audio-bytes")

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::OpenAI::TTS_1)
    posted["input"].as_s.should eq("hello")
    posted["voice"].as_s.should eq("alloy")
    posted["speed"].as_f.should eq(1.25)

    http_server.close
  end

  it "merges additional audio-generation params and surfaces provider errors" do
    server = FakeOpenAIAudioGenerationServer.new do |_request|
      {
        content_type: "text/plain",
        body:         "audio failed",
        status_code:  400,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::OpenAI::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")

    expect_raises(Crig::AudioGenerationError, /BAD_REQUEST: audio failed/) do
      client.audio_generation_model(Crig::Providers::OpenAI::TTS_1_HD)
        .audio_generation(
          Crig::AudioGenerationRequest.new(
            "hello",
            "alloy",
            1.0_f32,
            JSON.parse(%({"format":"wav"}))
          )
        )
    end

    posted = server.requests.first
    posted["format"].as_s.should eq("wav")

    http_server.close
  end
end
