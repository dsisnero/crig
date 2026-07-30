require "../../../spec_helper"

module Crig::Providers::Anthropic
  describe Content do
    it "parses code_execution_tool_result from JSON" do
      json = JSON.parse(%({
        "type": "code_execution_tool_result",
        "tool_use_id": "ce_1",
        "content": [
          {"type": "text", "text": "result: 42"}
        ]
      }))
      content = Content.from_json_value(json)
      content.kind.code_execution_tool_result?.should be_true
      content.tool_use_id.should eq("ce_1")
    end

    it "parses code_execution_tool_result with encrypted result" do
      json = JSON.parse(%({
        "type": "code_execution_tool_result",
        "tool_use_id": "ce_2",
        "content": [
          {"type": "text", "text": "Execution completed"},
          {"type": "encrypted_code_execution_result", "data": "encrypted-data"}
        ]
      }))
      content = Content.from_json_value(json)
      content.kind.code_execution_tool_result?.should be_true
      content.tool_use_id.should eq("ce_2")
    end

    it "serializes code_execution_tool_result back to JSON" do
      original = Content.code_execution_tool_result("ce_3", [ToolResultContent.text("done")])
      json = JSON.parse(original.to_json)
      json["type"].as_s.should eq("code_execution_tool_result")
      json["tool_use_id"].as_s.should eq("ce_3")
    end

    it "converts to core assistant content" do
      content = Content.code_execution_tool_result("ce_4", [ToolResultContent.text("output")])
      cc = content.to_core_assistant_content
      cc.kind.text?.should be_true
    end
  end
end
