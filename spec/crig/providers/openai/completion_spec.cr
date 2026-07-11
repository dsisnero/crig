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

module Crig::Providers::OpenAI
  describe OpenAIUsage do
    it "parses basic usage" do
      usage = OpenAIUsage.from_json(%({"prompt_tokens":10,"total_tokens":20}))
      usage.prompt_tokens.should eq(10)
      usage.total_tokens.should eq(20)
    end

    it "parses completion_tokens when present" do
      usage = OpenAIUsage.from_json(%({"prompt_tokens":10,"completion_tokens":8,"total_tokens":18}))
      usage.completion_tokens.should eq(8)
    end

    it "parses completion_tokens_details with reasoning_tokens" do
      usage = OpenAIUsage.from_json(%({"prompt_tokens":10,"completion_tokens":8,"total_tokens":18,"completion_tokens_details":{"reasoning_tokens":5}}))
      details = usage.completion_tokens_details
      details.should_not be_nil
      details.not_nil!.reasoning_tokens.should eq(5)
    end

    it "maps reasoning_tokens in token_usage" do
      usage = OpenAIUsage.from_json(%({"prompt_tokens":10,"completion_tokens":8,"total_tokens":18,"completion_tokens_details":{"reasoning_tokens":5}}))
      tu = usage.token_usage
      tu.should_not be_nil
      tu.not_nil!.reasoning_tokens.should eq(5)
    end

    it "parses timing fields" do
      usage = OpenAIUsage.from_json(%({"prompt_tokens":10,"total_tokens":20,"queue_time":0.5,"prompt_time":0.3,"completion_time":0.7,"total_time":1.0}))
      usage.queue_time.should eq(0.5)
      usage.prompt_time.should eq(0.3)
      usage.completion_time.should eq(0.7)
      usage.total_time.should eq(1.0)
    end

    it "output_tokens uses completion_tokens when available" do
      usage = OpenAIUsage.from_json(%({"prompt_tokens":10,"completion_tokens":8,"total_tokens":18}))
      tu = usage.to_crig_usage
      tu.output_tokens.should eq(8)
    end

    it "output_tokens falls back to total-prompt when completion_tokens absent" do
      usage = OpenAIUsage.from_json(%({"prompt_tokens":10,"total_tokens":20}))
      tu = usage.to_crig_usage
      tu.output_tokens.should eq(10)
    end
  end

  describe "CompletionError error paths" do
    it "non-success status preserves status and body via from_http_response" do
      err = Crig::Completion::CompletionError.from_http_response(503, "service unavailable")
      err.provider_response_status.should eq(503)
      err.provider_response_body.should eq("service unavailable")
    end

    it "api error body preserves body via from_provider_body" do
      err = Crig::Completion::CompletionError.from_provider_body(%({"error":{"message":"rate limit"}}))
      err.provider_response_status.should be_nil
      err.provider_response_body.should_not be_nil
    end
  end
end
