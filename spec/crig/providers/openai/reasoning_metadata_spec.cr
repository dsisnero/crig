require "../../../spec_helper"

module Crig::Providers::OpenAI
  describe "Responses API reasoning metadata" do
    it "exposes object-shaped reasoning metadata" do
      json = JSON.parse(%({
        "id": "resp_1",
        "object": "response",
        "created_at": 0,
        "status": "completed",
        "model": "gpt-5.6",
        "output": [],
        "tools": [],
        "reasoning": {"effort": "low", "summary": [{"type": "summary_text", "text": "step 1"}]}
      }))
      payload = CompletionResponsePayload.from_json(json.to_json)
      metadata = payload.reasoning_metadata
      metadata.should be_truthy
      metadata.not_nil!["effort"].as_s.should eq("low")
    end

    it "exposes string-shaped reasoning" do
      json = JSON.parse(%({
        "id": "resp_1",
        "object": "response",
        "created_at": 0,
        "status": "completed",
        "model": "gpt-5.6",
        "output": [],
        "tools": [],
        "reasoning": "step by step reasoning"
      }))
      payload = CompletionResponsePayload.from_json(json.to_json)
      metadata = payload.reasoning_metadata
      metadata.should be_truthy
      metadata.not_nil!.raw.should eq("step by step reasoning")
    end

    it "returns nil when reasoning field is absent" do
      json = JSON.parse(%({
        "id": "resp_1",
        "object": "response",
        "created_at": 0,
        "status": "completed",
        "model": "gpt-5.6",
        "output": [],
        "tools": []
      }))
      payload = CompletionResponsePayload.from_json(json.to_json)
      payload.reasoning_metadata.should be_nil
    end
  end
end
