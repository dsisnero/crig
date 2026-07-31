require "../../spec_helper"
describe Crig::Providers::HuggingFace do
  it "supports client initialization" do
    client = Crig::Providers::HuggingFace::Client.new("dummy-key")
    client_from_builder = Crig::Providers::HuggingFace::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::HuggingFace::HUGGINGFACE_API_BASE_URL)
  end

  it "uses the request model override when present" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello")),
      model: "meta-llama/Meta-Llama-3.1-8B-Instruct",
    )

    payload = Crig::Providers::HuggingFace::HuggingfaceCompletionRequest.from_request("mistralai/Mistral-7B", request)
    JSON.parse(payload.to_json)["model"].as_s.should eq("meta-llama/Meta-Llama-3.1-8B-Instruct")
  end

  it "uses the default model when the request does not override it" do
    request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello")),
    )

    payload = Crig::Providers::HuggingFace::HuggingfaceCompletionRequest.from_request("mistralai/Mistral-7B", request)
    JSON.parse(payload.to_json)["model"].as_s.should eq("mistralai/Mistral-7B")
  end

  it "deserializes assistant and user messages like the Rust tests" do
    assistant_message = Crig::Providers::HuggingFace::Message.from_json_value(JSON.parse(%(
      {"role":"assistant","content":"\\n\\nHello there, how may I assist you today?"}
    )))
    assistant_message2 = Crig::Providers::HuggingFace::Message.from_json_value(JSON.parse(%(
      {"role":"assistant","content":[{"type":"text","text":"\\n\\nHello there, how may I assist you today?"}],"tool_calls":null}
    )))
    assistant_message3 = Crig::Providers::HuggingFace::Message.from_json_value(JSON.parse(%(
      {"role":"assistant","tool_calls":[{"id":"call_h89ipqYUjEpCPI6SxspMnoUU","type":"function","function":{"name":"subtract","arguments":{"x":2,"y":5}}}],"content":null,"refusal":null}
    )))
    user_message = Crig::Providers::HuggingFace::Message.from_json_value(JSON.parse(%(
      {"role":"user","content":[{"type":"text","text":"What's in this image?"},{"type":"image_url","image_url":{"url":"https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"}}]}
    )))

    assistant_message.kind.assistant?.should be_true
    assistant_message.assistant_content[0].text.should eq("\n\nHello there, how may I assist you today?")

    assistant_message2.kind.assistant?.should be_true
    assistant_message2.assistant_content[0].text.should eq("\n\nHello there, how may I assist you today?")
    assistant_message2.tool_calls.should be_empty

    assistant_message3.kind.assistant?.should be_true
    assistant_message3.assistant_content.should be_empty
    assistant_message3.tool_calls[0].id.should eq("call_h89ipqYUjEpCPI6SxspMnoUU")
    assistant_message3.tool_calls[0].function.name.should eq("subtract")
    assistant_message3.tool_calls[0].function.arguments["x"].as_i.should eq(2)
    assistant_message3.tool_calls[0].function.arguments["y"].as_i.should eq(5)

    user_message.kind.user?.should be_true
    user_message.user_content.not_nil!.first.kind.text?.should be_true
    user_message.user_content.not_nil!.first.text.should eq("What's in this image?")
    user_message.user_content.not_nil!.to_a[1].kind.image_url?.should be_true
    user_message.user_content.not_nil!.to_a[1].image_url.not_nil!.url.should eq("https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg")
  end

  it "round-trips message conversion through the core message model" do
    user_message = Crig::Completion::Message.user("Hello")
    assistant_message = Crig::Completion::Message.assistant("Hi there!")

    converted_user = Crig::Providers::HuggingFace::Message.from_core_message(user_message)
    converted_assistant = Crig::Providers::HuggingFace::Message.from_core_message(assistant_message)

    converted_user[0].user_content.not_nil!.first.text.should eq("Hello")
    converted_assistant[0].assistant_content[0].text.should eq("Hi there!")

    converted_user[0].to_core_message.should eq(user_message)
    converted_assistant[0].to_core_message.should eq(assistant_message)
  end

  it "deserializes tool-call responses from multiple subproviders" do
    fireworks_response = Crig::Providers::HuggingFace::CompletionResponse.from_json(%(
      {"choices":[{"finish_reason":"tool_calls","index":0,"message":{"role":"assistant","tool_calls":[{"function":{"arguments":"{\\"x\\": 2, \\"y\\": 5}","name":"subtract"},"id":"call_1BspL6mQqjKgvsQbH1TIYkHf","index":0,"type":"function"}]}}],"created":1740704000,"id":"2a81f6a1-4866-42fb-9902-2655a2b5b1ff","model":"accounts/fireworks/models/deepseek-v3","object":"chat.completion","usage":{"completion_tokens":26,"prompt_tokens":248,"total_tokens":274}}
    ))
    novita_response = Crig::Providers::HuggingFace::CompletionResponse.from_json(%(
      {"choices":[{"finish_reason":"tool_calls","index":0,"logprobs":null,"message":{"audio":null,"content":null,"function_call":null,"reasoning_content":null,"refusal":null,"role":"assistant","tool_calls":[{"function":{"arguments":"{\\"x\\": \\"2\\", \\"y\\": \\"5\\"}","name":"subtract"},"id":"chatcmpl-tool-f6d2af7c8dc041058f95e2c2eede45c5","type":"function"}]},"stop_reason":128008}],"created":1740704592,"id":"chatcmpl-a92c60ae125c47c998ecdcb53387fed4","model":"meta-llama/Meta-Llama-3.1-8B-Instruct-fast","object":"chat.completion","prompt_logprobs":null,"service_tier":null,"system_fingerprint":null,"usage":{"completion_tokens":28,"completion_tokens_details":null,"prompt_tokens":335,"prompt_tokens_details":null,"total_tokens":363}}
    ))

    fireworks_response.choices.first.message.tool_calls.first.function.arguments["x"].as_i.should eq(2)
    novita_response.choices.first.message.tool_calls.first.function.arguments["x"].as_s.should eq("2")
  end

  it "silently skips assistant reasoning-only history items" do
    assistant = Crig::Completion::Message.new(
      Crig::Completion::Message::Role::Assistant,
      Crig::OneOrMany(Crig::Completion::UserContent | Crig::Completion::AssistantContent).one(
        Crig::Completion::AssistantContent.reasoning("hidden").as(Crig::Completion::UserContent | Crig::Completion::AssistantContent)
      ),
    )

    Crig::Providers::HuggingFace::Message.from_core_message(assistant).should eq([] of Crig::Providers::HuggingFace::Message)
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

    converted = Crig::Providers::HuggingFace::Message.from_core_message(assistant)

    converted.size.should eq(1)
    converted[0].assistant_content.map(&.text).should eq(["visible"])
    converted[0].tool_calls.size.should eq(1)
    converted[0].tool_calls[0].id.should eq("call_1")
    converted[0].tool_calls[0].function.name.should eq("subtract")
    converted[0].tool_calls[0].function.arguments["x"].as_i.should eq(2)
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

    expect_raises(Crig::Completion::CompletionError, "HuggingFace request has no provider-compatible messages after conversion") do
      Crig::Providers::HuggingFace::HuggingfaceCompletionRequest.from_request("meta/test-model", request)
    end
  end
end
