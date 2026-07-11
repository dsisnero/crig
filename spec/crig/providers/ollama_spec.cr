require "../../spec_helper"

module Crig::Providers::Ollama
  describe OllamaCompletionRequest do
    it "omits think when not specified" do
      req = Crig::Completion::Request::CompletionRequestBuilder.new("hello").build
      ollama_req = OllamaCompletionRequest.from_request(LLAMA3_2, req)
      ollama_req.think.should be_nil
    end

    it "serializes think as bool" do
      req = Crig::Completion::Request::CompletionRequestBuilder.new("hello")
        .additional_params(JSON.parse(%({"think":true})))
        .build
      ollama_req = OllamaCompletionRequest.from_request(LLAMA3_2, req)
      ollama_req.think.should eq(true)
    end

    it "serializes think as level string" do
      req = Crig::Completion::Request::CompletionRequestBuilder.new("hello")
        .additional_params(JSON.parse(%({"think":"max"})))
        .build
      ollama_req = OllamaCompletionRequest.from_request(LLAMA3_2, req)
      ollama_req.think.should eq("max")
    end
  end

  describe CompletionResponse do
    it "preserves thinking as reasoning in completion response" do
      json = JSON.parse(%({
        "model": "qwen3",
        "created_at": "2023-01-01T00:00:00Z",
        "message": {
          "role": "assistant",
          "content": "",
          "thinking": "step one"
        },
        "done": true,
        "done_reason": "stop",
        "total_duration": 1000,
        "load_duration": 100,
        "prompt_eval_count": 10,
        "prompt_eval_duration": 200,
        "eval_count": 20,
        "eval_duration": 800
      }))
      response = CompletionResponse.from_json(json.to_json)
      crig_resp = response.to_completion_response
      has_reasoning = crig_resp.choice.any? { |c| c.kind.reasoning? }
      has_reasoning.should be_true
    end
  end
end
