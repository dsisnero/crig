require "../../spec_helper"

module Crig::Providers::DeepSeek
  describe DeepseekCompletionRequest do
    it "suppresses Required tool_choice when thinking is not disabled" do
      req = Crig::Completion::Request::CompletionRequestBuilder.new("Use a tool.")
        .tool(Crig::Completion::ToolDefinition.new("alpha", "Alpha tool", JSON.parse(%({"type":"object","properties":{},"required":[]}))))
        .tool_choice(Crig::Completion::ToolChoice.required)
        .build

      ds_req = DeepseekCompletionRequest.from_request("deepseek-v4-flash", req)

      ds_req.tool_choice.should be_nil
    end

    it "serializes Specific tool_choice when thinking is disabled" do
      req = Crig::Completion::Request::CompletionRequestBuilder.new("Use a tool.")
        .tool(Crig::Completion::ToolDefinition.new("alpha", "Alpha tool", JSON.parse(%({"type":"object","properties":{},"required":[]}))))
        .tool(Crig::Completion::ToolDefinition.new("beta", "Beta tool", JSON.parse(%({"type":"object","properties":{},"required":[]}))))
        .tool_choice(Crig::Completion::ToolChoice.specific(["beta"]))
        .additional_params(JSON.parse(%({"thinking":{"type":"disabled"}})))
        .build

      ds_req = DeepseekCompletionRequest.from_request("deepseek-v4-flash", req)

      ds_req.tool_choice.should_not be_nil
      ds_req.tool_choice.to_json.should contain("beta")
    end

    it "suppresses Specific tool_choice when thinking is not disabled" do
      req = Crig::Completion::Request::CompletionRequestBuilder.new("Use a tool.")
        .tool(Crig::Completion::ToolDefinition.new("beta", "Beta tool", JSON.parse(%({"type":"object","properties":{},"required":[]}))))
        .tool_choice(Crig::Completion::ToolChoice.specific(["beta"]))
        .build

      ds_req = DeepseekCompletionRequest.from_request("deepseek-v4-flash", req)

      ds_req.tool_choice.should be_nil
    end
  end

  describe "usage with reasoning tokens" do
    it "parses reasoning_tokens from completion_tokens_details" do
      usage = Usage.from_json(%({"completion_tokens":8,"prompt_tokens":10,"total_tokens":18,"completion_tokens_details":{"reasoning_tokens":5},"prompt_tokens_details":{"cached_tokens":3},"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":10}))
      tu = usage.token_usage
      tu.should_not be_nil
      tu.not_nil!.reasoning_tokens.should eq(5)
      tu.not_nil!.cached_input_tokens.should eq(3)
    end
  end

  describe "model constants" do
    it "defines DEEPSEEK_V4_FLASH" do
      DEEPSEEK_V4_FLASH.should eq("deepseek-v4-flash")
    end

    it "defines DEEPSEEK_V4_PRO" do
      DEEPSEEK_V4_PRO.should eq("deepseek-v4-pro")
    end
  end
end
