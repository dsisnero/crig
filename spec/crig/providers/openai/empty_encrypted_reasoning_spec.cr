require "../../../spec_helper"

module Crig::Providers::OpenAI
  describe "empty encrypted reasoning" do
    it "non-streaming: omits empty encrypted content" do
      reasoning = OutputReasoning.from_json(%({"id":"r_01","summary":[],"encrypted_content":""}))
      content = reasoning.to_completion_content
      # Should have no reasoning content because encrypted is empty
      content.reasoning.should be_truthy
      content.reasoning.try { |r| r.content.size.should eq(0) }
    end

    it "non-streaming: preserves non-empty encrypted content" do
      reasoning = OutputReasoning.from_json(%({"id":"r_01","summary":[],"encrypted_content":"encrypted-data"}))
      content = reasoning.to_completion_content
      content.reasoning.should be_truthy
      content.reasoning.try { |r| r.content.size.should eq(1) }
    end

    it "non-streaming: includes summary even when encrypted is empty" do
      reasoning = OutputReasoning.from_json(%({"id":"r_01","summary":[{"text":"step 1"}],"encrypted_content":""}))
      content = reasoning.to_completion_content
      content.reasoning.should be_truthy
      content.reasoning.try { |r| r.content.size.should eq(1) }
      content.reasoning.try { |r| r.content.first.kind.summary?.should be_true }
    end
  end
end
