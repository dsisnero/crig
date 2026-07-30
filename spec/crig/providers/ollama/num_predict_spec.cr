require "../../../spec_helper"

module Crig::Providers::Ollama
  describe "Ollama num_predict" do
    it "maps max_tokens to options.num_predict, not top-level" do
      req = OllamaCompletionRequest.new(
        model: "test-model",
        messages: [] of Message,
        max_tokens: 1024_i64,
        options: JSON.parse(%({"temperature":0.7})),
      )

      json = req.to_json
      parsed = JSON.parse(json)

      # max_tokens should NOT be a top-level field
      parsed.as_h.has_key?("max_tokens").should be_false

      # num_predict should be in options
      options = parsed["options"].as_h
      options["num_predict"].should eq(1024)
    end

    it "includes temperature in options, not top-level" do
      req = OllamaCompletionRequest.new(
        model: "test-model",
        messages: [] of Message,
        temperature: 0.7,
        options: JSON.parse(%({"temperature":0.7})),
      )

      json = req.to_json
      parsed = JSON.parse(json)

      # temperature should NOT be a top-level field
      parsed.as_h.has_key?("temperature").should be_false

      # temperature should be in options
      options = parsed["options"].as_h
      options["temperature"].should eq(0.7)
    end

    it "from_request maps max_tokens to options" do
      core_req = Crig::Completion::Request::CompletionRequest.new(
        chat_history: Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("hello")),
        model: "test-model",
        max_tokens: 512_i64,
      )

      req = OllamaCompletionRequest.from_request("default", core_req)
      json = req.to_json
      parsed = JSON.parse(json)

      parsed.as_h.has_key?("max_tokens").should be_false

      options = parsed["options"].as_h
      options["num_predict"].should eq(512)
    end
  end
end
