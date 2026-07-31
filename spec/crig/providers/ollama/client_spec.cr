require "../../../spec_helper"
describe Crig::Providers::Ollama do
  it "supports client initialization" do
    client = Crig::Providers::Ollama::Client.new(Crig::Nothing.new)
    from_builder = Crig::Providers::Ollama::Client.builder.api_key(Crig::Nothing.new).build

    client.base_url.should eq(Crig::Providers::Ollama::OLLAMA_API_BASE_URL)
    from_builder.base_url.should eq(Crig::Providers::Ollama::OLLAMA_API_BASE_URL)
  end

  it "converts tool definitions to ollama format" do
    internal_tool = Crig::Completion::ToolDefinition.new(
      "get_current_weather",
      "Get the current weather for a location",
      JSON.parse(%({
        "type":"object",
        "properties":{"location":{"type":"string"}},
        "required":["location"]
      }))
    )

    ollama_tool = Crig::Providers::Ollama::ToolDefinition.from_core(internal_tool)

    ollama_tool.type_field.should eq("function")
    ollama_tool.function.name.should eq("get_current_weather")
    ollama_tool.function.parameters["properties"]["location"]["type"].as_s.should eq("string")
  end

  it "converts provider messages back into core messages" do
    provider_msg = Crig::Providers::Ollama::Message.user("Test message")
    comp_msg = provider_msg.to_core_message

    comp_msg.role.user?.should be_true
    first_content = comp_msg.content.first.as(Crig::Completion::UserContent)
    first_content.kind.text?.should be_true
    first_content.text.not_nil!.text.should eq("Test message")
  end

  it "converts assistant reasoning into ollama thinking" do
    internal_msg = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).many([
        Crig::Completion::AssistantContent.reasoning("Step 1: Consider the problem").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
        Crig::Completion::AssistantContent.text("The answer is X").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent),
      ])
    )

    provider_msgs = Crig::Providers::Ollama::Message.from_core_message(internal_msg)

    provider_msgs.size.should eq(1)
    provider_msg = provider_msgs.first
    provider_msg.kind.assistant?.should be_true
    provider_msg.thinking.should eq("Step 1: Consider the problem")
    provider_msg.content.should eq("The answer is X")
  end

  it "deserializes chat responses with thinking content" do
    sample = JSON.parse(%({
      "model":"qwen-thinking",
      "created_at":"2023-08-04T19:22:45.499127Z",
      "message":{"role":"assistant","content":"The answer is 42.","thinking":"Let me think about this carefully.","images":null,"tool_calls":[]},
      "done":true,
      "total_duration":8000000000,
      "load_duration":6000000,
      "prompt_eval_count":61,
      "prompt_eval_duration":400000000,
      "eval_count":468,
      "eval_duration":7700000000
    }))

    chat_resp = Crig::Providers::Ollama::CompletionResponse.from_json(sample.to_json)

    chat_resp.message.kind.assistant?.should be_true
    chat_resp.message.thinking.should eq("Let me think about this carefully.")
    chat_resp.message.content.should eq("The answer is 42.")
  end

  it "keeps empty thinking content when deserializing" do
    sample = JSON.parse(%({
      "model":"llama3.2",
      "created_at":"2023-08-04T19:22:45.499127Z",
      "message":{"role":"assistant","content":"Response","thinking":"","images":null,"tool_calls":[]},
      "done":true
    }))

    chat_resp = Crig::Providers::Ollama::CompletionResponse.from_json(sample.to_json)

    chat_resp.message.thinking.should eq("")
    chat_resp.message.content.should eq("Response")
  end

  it "deserializes streaming responses with thinking content" do
    sample = JSON.parse(%({
      "model":"qwen-thinking",
      "created_at":"2023-08-04T19:22:45.499127Z",
      "message":{"role":"assistant","content":"","thinking":"Analyzing the problem...","images":null,"tool_calls":[]},
      "done":false
    }))

    chunk = Crig::Providers::Ollama::CompletionResponse.from_json(sample.to_json)

    chunk.message.thinking.should eq("Analyzing the problem...")
    chunk.message.content.should eq("")
  end

  it "deserializes thinking responses with tool calls" do
    sample = JSON.parse(%({
      "model":"qwen-thinking",
      "created_at":"2023-08-04T19:22:45.499127Z",
      "message":{
        "role":"assistant",
        "content":"Let me check the weather.",
        "thinking":"User wants weather info, I should use the weather tool",
        "images":null,
        "tool_calls":[{"type":"function","function":{"name":"get_weather","arguments":{"location":"San Francisco"}}}]
      },
      "done":true
    }))

    chat_resp = Crig::Providers::Ollama::CompletionResponse.from_json(sample.to_json)

    chat_resp.message.thinking.should eq("User wants weather info, I should use the weather tool")
    chat_resp.message.content.should eq("Let me check the weather.")
    chat_resp.message.tool_calls.size.should eq(1)
    chat_resp.message.tool_calls.first.function.name.should eq("get_weather")
  end

  it "extracts think and keep_alive as top-level request params" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("What is 2 + 2?")),
      preamble: "You are a helpful assistant.",
      temperature: 0.7,
      max_tokens: 1024,
      additional_params: JSON.parse(%({"think":true,"keep_alive":"-1m","num_ctx":4096}))
    )

    ollama_request = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("qwen3:8b", completion_request)
    serialized = JSON.parse(ollama_request.to_json)

    serialized.should eq(JSON.parse(%({
      "model":"qwen3:8b",
      "messages":[
        {"role":"system","content":"You are a helpful assistant."},
        {"role":"user","content":"What is 2 + 2?"}
      ],
      "stream":false,
      "think":true,
      "keep_alive":"-1m",
      "options":{"temperature":0.7,"num_ctx":4096,"num_predict":1024}
    })))
  end

  it "omits think when omitted so Ollama can use the model default" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello!")),
      preamble: "You are a helpful assistant.",
      temperature: 0.5
    )

    ollama_request = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("llama3.2", completion_request)
    serialized = JSON.parse(ollama_request.to_json)

    serialized.should eq(JSON.parse(%({
      "model":"llama3.2",
      "messages":[
        {"role":"system","content":"You are a helpful assistant."},
        {"role":"user","content":"Hello!"}
      ],
      "stream":false,
      "options":{"temperature":0.5}
    })))
  end

  it "serializes output schema into format" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("How old is Ollama?")),
      model: "llama3.1",
      output_schema: JSON.parse(%({
        "type":"object",
        "properties":{"age":{"type":"integer"},"available":{"type":"boolean"}},
        "required":["age","available"]
      }))
    )

    ollama_request = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("llama3.1", completion_request)
    serialized = JSON.parse(ollama_request.to_json)

    serialized["format"].should eq(JSON.parse(%({
      "type":"object",
      "properties":{"age":{"type":"integer"},"available":{"type":"boolean"}},
      "required":["age","available"]
    })))
  end

  it "omits format when there is no output schema" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello!")),
      model: "llama3.1"
    )

    ollama_request = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("llama3.1", completion_request)
    serialized = JSON.parse(ollama_request.to_json)

    serialized.as_h.has_key?("format").should be_false
  end

  it "extracts think level low param" do
    req = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("What is 2 + 2?")),
      preamble: "You are a helpful assistant.",
      temperature: 0.7,
      max_tokens: 1024,
      additional_params: JSON.parse(%({"think":"low","keep_alive":"-1m","num_ctx":4096}))
    )
    ollama = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("qwen3:8b", req)
    json = JSON.parse(ollama.to_json)
    json["think"].as_s.should eq("low")
    json["keep_alive"].as_s.should eq("-1m")
    json["options"]["num_ctx"].as_i.should eq(4096)
  end

  it "extracts think level medium param" do
    req = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("What is 2 + 2?")),
      preamble: "You are a helpful assistant.",
      temperature: 0.7,
      max_tokens: 1024,
      additional_params: JSON.parse(%({"think":"medium","keep_alive":"-1m","num_ctx":4096}))
    )
    ollama = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("qwen3:8b", req)
    json = JSON.parse(ollama.to_json)
    json["think"].as_s.should eq("medium")
  end

  it "extracts think level high param" do
    req = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("What is 2 + 2?")),
      preamble: "You are a helpful assistant.",
      temperature: 0.7,
      max_tokens: 1024,
      additional_params: JSON.parse(%({"think":"high","keep_alive":"-1m","num_ctx":4096}))
    )
    ollama = Crig::Providers::Ollama::OllamaCompletionRequest.from_request("qwen3:8b", req)
    json = JSON.parse(ollama.to_json)
    json["think"].as_s.should eq("high")
  end

  it "rejects invalid think param" do
    req = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("What is 2 + 2?")),
      preamble: "You are a helpful assistant.",
      temperature: 0.7,
      max_tokens: 1024,
      additional_params: JSON.parse(%({"think":"ultra","keep_alive":"-1m","num_ctx":4096}))
    )
    expect_raises(Crig::Completion::CompletionError, /think/) do
      Crig::Providers::Ollama::OllamaCompletionRequest.from_request("qwen3:8b", req)
    end
  end
end
