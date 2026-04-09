require "../../../spec_helper"

describe Crig::Providers::OpenAI::Chat::CompletionResponse do
  it "deserializes tool calls with raw object arguments" do
    response = Crig::Providers::OpenAI::Chat::CompletionResponse.from_json_value(JSON.parse(%({
      "choices": [{
        "finish_reason": "tool_calls",
        "index": 0,
        "message": {
          "role": "assistant",
          "content": "",
          "tool_calls": [{ "type": "function", "function": { "name": "hello_world", "arguments": { "city": "Paris" } }, "id": "xxx" }]
        }
      }],
      "created": 0,
      "model": "gpt-4o-mini",
      "system_fingerprint": "fp_xxx",
      "object": "chat.completion",
      "usage": { "prompt_tokens": 255, "total_tokens": 268 },
      "id": "xxx"
    })))

    tool_call = response.choices.first.message.tool_calls.first
    tool_call.id.should eq("xxx")
    tool_call.function.name.should eq("hello_world")
    tool_call.function.arguments["city"].as_s.should eq("Paris")
  end

  it "deserializes tool calls with stringified json arguments" do
    response = Crig::Providers::OpenAI::Chat::CompletionResponse.from_json_value(JSON.parse(%({
      "choices": [{
        "finish_reason": "tool_calls",
        "index": 0,
        "message": {
          "role": "assistant",
          "content": "",
          "tool_calls": [{ "type": "function", "function": { "name": "hello_world", "arguments": "{\\"city\\":\\"Paris\\"}" }, "id": "xxx" }]
        }
      }],
      "created": 0,
      "model": "gpt-4o-mini",
      "system_fingerprint": "fp_xxx",
      "object": "chat.completion",
      "usage": { "prompt_tokens": 255, "total_tokens": 268 },
      "id": "xxx"
    })))

    tool_call = response.choices.first.message.tool_calls.first
    tool_call.function.arguments["city"].as_s.should eq("Paris")
  end
end
