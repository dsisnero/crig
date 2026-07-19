require "../../../spec_helper"

module Crig::Providers::Anthropic
  describe Anthropic do
    it "coerce_tool_input passes through objects unchanged" do
      result = Anthropic.coerce_tool_input(JSON.parse(%({"q":"rust","n":3})))
      result["q"].as_s.should eq("rust")
      result["n"].as_i.should eq(3)
    end

    it "coerce_tool_input parses JSON string into object" do
      result = Anthropic.coerce_tool_input(JSON.parse(%("{\\"q\\":\\"rust\\"}")))
      result["q"].as_s.should eq("rust")
    end

    it "coerce_tool_input collapses non-JSON string to empty object" do
      result = Anthropic.coerce_tool_input(JSON.parse(%("not json")))
      result.as_h.should be_empty
    end

    it "coerce_tool_input collapses null to empty object" do
      result = Anthropic.coerce_tool_input(JSON.parse("null"))
      result.as_h.should be_empty
    end

    it "coerce_tool_input collapses array to empty object" do
      result = Anthropic.coerce_tool_input(JSON.parse("[1,2,3]"))
      result.as_h.should be_empty
    end

    it "composes_native_output_with_tools returns true for Anthropic model" do
      client = Client.new("test-key")
      model = client.completion_model(CLAUDE_SONNET_4_6)
      model.composes_native_output_with_tools?.should be_true
    end
  end

  describe "Content text citations" do
    it "deserializes null citations as empty vec" do
      content = Content.from_json_value(JSON.parse(%({"type":"text","text":"hello","citations":null})))
      content.text.should eq("hello")
      content.citations.not_nil!.should eq([] of Citation)
    end

    it "deserializes missing citations as nil" do
      content = Content.from_json_value(JSON.parse(%({"type":"text","text":"hello"})))
      content.text.should eq("hello")
      content.citations.should be_nil
    end
  end
end
