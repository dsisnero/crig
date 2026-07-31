require "../../../spec_helper"
describe Crig::Providers::Cohere::Client do
  it "ports the cohere client initialization and embedding helpers" do
    client = Crig::Providers::Cohere::Client.new("dummy-key")
    builder_client = Crig::Providers::Cohere::Client.builder
      .api_key("dummy-key")
      .build

    client.api_key.should eq("dummy-key")
    builder_client.api_key.should eq("dummy-key")
    client.default_headers["authorization"].should eq("Bearer dummy-key")

    english = client.embedding_model(Crig::Providers::Cohere::EMBED_ENGLISH_V3, "search_document")
    english.model.should eq(Crig::Providers::Cohere::EMBED_ENGLISH_V3)
    english.ndims.should eq(1024)
    english.input_type.should eq("search_document")

    custom = client.embedding_model_with_ndims("custom", "search_query", 777)
    custom.ndims.should eq(777)
    custom.input_type.should eq("search_query")
  end

  it "builds cohere embeddings builders with input_type-specific helpers" do
    client = Crig::Providers::Cohere::Client.new("dummy-key")

    builder = client.embeddings(Crig::SimpleDocument, Crig::Providers::Cohere::EMBED_ENGLISH_V3, "search_document")
      .simple_document("doc0", "Hello, world!")
    builder.model.input_type.should eq("search_document")
    builder.model.ndims.should eq(1024)
    builder.documents.map(&.[0].id).should eq(["doc0"])

    custom = client.embeddings_with_ndims("custom-model", "search_query", 333)
      .simple_document("doc1", "Goodbye, world!")
    custom.model.input_type.should eq("search_query")
    custom.model.ndims.should eq(333)
    custom.documents.map(&.[0].id).should eq(["doc1"])
  end

  it "posts cohere embedding requests and parses responses" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.content_type = "application/json"
      context.response.print(%({
        "id":"embed_123",
        "response_type":"embeddings_floats",
        "embeddings":[[0.1,0.2],[0.3,0.4]],
        "texts":["alpha","beta"],
        "meta":{
          "api_version":{"version":"1"},
          "billed_units":{"input_tokens":4,"output_tokens":0,"search_units":1,"classifications":0},
          "warnings":[]
        }
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

    client = Crig::Providers::Cohere::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.embedding_model(Crig::Providers::Cohere::EMBED_ENGLISH_V3, "search_document")
    embeddings = model.embed_texts(["alpha", "beta"])

    embeddings.size.should eq(2)
    embeddings[0].document.should eq("alpha")
    embeddings[0].vec.should eq([0.1, 0.2])
    embeddings[1].document.should eq("beta")
    embeddings[1].vec.should eq([0.3, 0.4])
    requests.first["model"].as_s.should eq(Crig::Providers::Cohere::EMBED_ENGLISH_V3)
    requests.first["input_type"].as_s.should eq("search_document")
    requests.first["texts"].as_a.map(&.as_s).should eq(["alpha", "beta"])

    http_server.close
  end
end

describe Crig::Providers::Cohere::CompletionResponse do
  it "deserializes the Rust cohere completion response shape" do
    response = Crig::Providers::Cohere::CompletionResponse.from_json_value(JSON.parse(%({
      "id":"abc123",
      "message":{
        "role":"assistant",
        "tool_plan":"I will use the subtract tool to find the difference between 2 and 5.",
        "tool_calls":[
          {
            "id":"subtract_sm6ps6fb6y9f",
            "type":"function",
            "function":{"name":"subtract","arguments":"{\\"x\\":5,\\"y\\":2}"}
          }
        ]
      },
      "finish_reason":"TOOL_CALL",
      "usage":{
        "billed_units":{"input_tokens":78,"output_tokens":27},
        "tokens":{"input_tokens":1028,"output_tokens":63}
      }
    })))

    content, citations, tool_calls = response.message
    response.id.should eq("abc123")
    response.finish_reason.tool_call?.should be_true
    response.usage.not_nil!.billed_units.not_nil!.input_tokens.should eq(78.0)
    response.usage.not_nil!.billed_units.not_nil!.output_tokens.should eq(27.0)
    response.usage.not_nil!.tokens.not_nil!.input_tokens.should eq(1028.0)
    response.usage.not_nil!.tokens.not_nil!.output_tokens.should eq(63.0)
    content.should eq([] of Crig::Providers::Cohere::AssistantContent)
    citations.should eq([] of Crig::Providers::Cohere::Citation)
    tool_calls.size.should eq(1)
    tool_calls.first.function.not_nil!.name.should eq("subtract")
    tool_calls.first.function.not_nil!.arguments["x"].as_i.should eq(5)
    tool_calls.first.function.not_nil!.arguments["y"].as_i.should eq(2)
  end
end

describe Crig::Providers::Cohere::Message do
  it "converts a core completion message to cohere messages and back" do
    completion_message = Crig::Completion::Message.user("Hello, world!")

    messages = Crig::Providers::Cohere::Message.from_core_message(completion_message)
    converted_back = messages.map(&.to_core_message)

    converted_back.size.should eq(1)
    converted_back.first.role.user?.should be_true
    converted_back.first.content.first.as(Crig::Completion::UserContent).text.not_nil!.text.should eq("Hello, world!")
  end

  it "converts a cohere message to a core completion message and back" do
    message = Crig::Providers::Cohere::Message.user(
      Crig::OneOrMany(Crig::Providers::Cohere::UserContent).one(
        Crig::Providers::Cohere::UserContent.text("Hello, world!")
      )
    )

    completion_message = message.to_core_message
    converted_back = Crig::Providers::Cohere::Message.from_core_message(completion_message)

    converted_back.size.should eq(1)
    converted_back.first.user_content.not_nil!.first.text.should eq("Hello, world!")
  end
end

describe Crig::Providers::Cohere::Citation do
  it "parses citation types and source variants" do
    citation = Crig::Providers::Cohere::Citation.from_json_value(JSON.parse(%({
      "start":1,
      "end":4,
      "text":"test",
      "type":"TEXT_CONTENT",
      "sources":[
        {"type":"document","id":"doc-1","document":{"title":"Doc"}},
        {"type":"tool","id":"call-1","tool_output":{"status":"ok"}}
      ]
    })))

    citation.citation_type.not_nil!.value.should eq("TEXT_CONTENT")
    citation.sources.map(&.kind).should eq([
      Crig::Providers::Cohere::Source::Kind::Document,
      Crig::Providers::Cohere::Source::Kind::Tool,
    ])

    roundtrip = JSON.parse(citation.to_json)
    roundtrip["type"].as_s.should eq("TEXT_CONTENT")
    roundtrip["sources"].as_a.size.should eq(2)
  end
end

describe Crig::Providers::Cohere::UserContent do
  it "parses image_url payloads and converts them back to core messages" do
    content = Crig::Providers::Cohere::UserContent.from_json_value(JSON.parse(%({
      "type":"image_url",
      "image_url":{"url":"https://example.com/cat.png"}
    })))

    content.kind.image_url?.should be_true
    content.image_url.not_nil!.url.should eq("https://example.com/cat.png")

    message = Crig::Providers::Cohere::Message.user(Crig::OneOrMany(Crig::Providers::Cohere::UserContent).one(content))
    core = message.to_core_message
    core_content = core.content.first.as(Crig::Completion::UserContent)
    core_content.image.not_nil!.try_into_url.should eq("https://example.com/cat.png")
  end
end

describe Crig::Providers::Cohere::ToolResultContent do
  it "parses document payloads and converts them back to core tool results" do
    content = Crig::Providers::Cohere::ToolResultContent.from_json_value(JSON.parse(%({
      "document":{"id":"doc-1","data":{"text":"hello"}}
    })))

    content.kind.document?.should be_true
    content.document.not_nil!.id.should eq("doc-1")

    message = Crig::Providers::Cohere::Message.tool(
      Crig::OneOrMany(Crig::Providers::Cohere::ToolResultContent).one(content),
      "call-1"
    )
    core = message.to_core_message
    tool_result = core.content.first.as(Crig::Completion::UserContent).tool_result.not_nil!
    tool_result.id.should eq("call-1")
    tool_result.content.first.text.not_nil!.text.should eq(%({"text":"hello"}))
  end
end

describe Crig::Providers::Cohere::CompletionModel do
  it "supports direct constructor parity" do
    client = Crig::Providers::Cohere::Client.new("dummy-key")
    model = Crig::Providers::Cohere::CompletionModel.new(client, Crig::Providers::Cohere::COMMAND_R)

    model.client.should eq(client)
    model.model.should eq(Crig::Providers::Cohere::COMMAND_R)
  end

  it "posts cohere chat requests and parses responses" do
    requests = [] of JSON::Any
    http_server = HTTP::Server.new do |context|
      requests << JSON.parse(context.request.body.not_nil!.gets_to_end)
      context.response.content_type = "application/json"
      context.response.print(%({
        "id":"cohere_chat_1",
        "message":{"role":"assistant","content":[{"type":"text","text":"Hello from Cohere"}],"citations":[],"tool_calls":[]},
        "finish_reason":"COMPLETE",
        "usage":{"tokens":{"input_tokens":12,"output_tokens":5}}
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

    client = Crig::Providers::Cohere::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    model = client.completion_model(Crig::Providers::Cohere::COMMAND_R)
    response = model.completion(
      model.completion_request("Hello Cohere")
        .tool(Crig::Completion::ToolDefinition.new("subtract", "Subtract numbers", JSON.parse(%({"type":"object"}))))
        .temperature(0.5)
        .build
    )

    response.choice.first.text.not_nil!.text.should eq("Hello from Cohere")
    response.usage.input_tokens.should eq(12_i64)
    response.usage.output_tokens.should eq(5_i64)
    requests.first["model"].as_s.should eq(Crig::Providers::Cohere::COMMAND_R)
    requests.first["messages"].as_a.size.should eq(1)
    requests.first["messages"].as_a.first["role"].as_s.should eq("user")
    requests.first["messages"].as_a.first["content"].as_a.first["text"].as_s.should eq("Hello Cohere")
    requests.first["tools"].as_a.first["function"]["name"].as_s.should eq("subtract")

    http_server.close
  end
end

describe Crig::Providers::Cohere::Streaming::StreamingEvent do
  it "deserializes a content delta event" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({
      "type":"content-delta",
      "delta":{"message":{"content":{"text":"Hello world"}}}
    })))

    event.kind.content_delta?.should be_true
    event.delta.not_nil!.message.not_nil!.content.not_nil!.text.should eq("Hello world")
  end

  it "deserializes a tool call start event" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({
      "type":"tool-call-start",
      "delta":{"message":{"tool_calls":{"id":"call_123","function":{"name":"get_weather","arguments":"{"}}}}
    })))

    event.kind.tool_call_start?.should be_true
    tool_call = event.delta.not_nil!.message.not_nil!.tool_calls.not_nil!
    tool_call.id.should eq("call_123")
    tool_call.function.not_nil!.name.should eq("get_weather")
  end

  it "deserializes a tool call delta event" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({
      "type":"tool-call-delta",
      "delta":{"message":{"tool_calls":{"function":{"arguments":"\\"location\\""}}}}
    })))

    event.kind.tool_call_delta?.should be_true
    event.delta.not_nil!.message.not_nil!.tool_calls.not_nil!.function.not_nil!.arguments.should eq(%("location"))
  end

  it "deserializes a tool call end event" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({"type":"tool-call-end"})))

    event.kind.tool_call_end?.should be_true
  end

  it "deserializes a message end event with usage" do
    event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(JSON.parse(%({
      "type":"message-end",
      "delta":{"usage":{"tokens":{"input_tokens":100,"output_tokens":50}}}
    })))

    event.kind.message_end?.should be_true
    usage = event.message_end_delta.not_nil!.usage.not_nil!
    usage.tokens.not_nil!.input_tokens.should eq(100.0)
    usage.tokens.not_nil!.output_tokens.should eq(50.0)
  end

  it "deserializes the Rust streaming event order sequence" do
    events = [
      JSON.parse(%({"type":"message-start"})),
      JSON.parse(%({"type":"content-start"})),
      JSON.parse(%({"type":"content-delta","delta":{"message":{"content":{"text":"Sure, "}}}})),
      JSON.parse(%({"type":"content-delta","delta":{"message":{"content":{"text":"I can help with that."}}}})),
      JSON.parse(%({"type":"content-end"})),
      JSON.parse(%({"type":"tool-plan"})),
      JSON.parse(%({"type":"tool-call-start","delta":{"message":{"tool_calls":{"id":"call_abc","function":{"name":"search","arguments":""}}}}})),
      Crig::Providers::OpenAI.build_json_any do |json|
        json.object do
          json.field "type", "tool-call-delta"
          json.field "delta" do
            json.object do
              json.field "message" do
                json.object do
                  json.field "tool_calls" do
                    json.object do
                      json.field "function" do
                        json.object do
                          json.field "arguments", "{\"query\":"
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end,
      Crig::Providers::OpenAI.build_json_any do |json|
        json.object do
          json.field "type", "tool-call-delta"
          json.field "delta" do
            json.object do
              json.field "message" do
                json.object do
                  json.field "tool_calls" do
                    json.object do
                      json.field "function" do
                        json.object do
                          json.field "arguments", "\"Rust\"}"
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end,
      JSON.parse(%({"type":"tool-call-end"})),
      JSON.parse(%({"type":"message-end","delta":{"usage":{"tokens":{"input_tokens":50,"output_tokens":25}}}})),
    ]

    events.each_with_index do |event_json, index|
      begin
        event = Crig::Providers::Cohere::Streaming::StreamingEvent.from_json_value(event_json)
        event.should be_a(Crig::Providers::Cohere::Streaming::StreamingEvent)
      rescue ex
        fail "Failed to deserialize event at index #{index}: #{ex.message}"
      end
    end
  end
end
