require "../../spec_helper"

module Crig
  describe MultiTurnStreamItem do
    it "tool_execution_committed carries tool results" do
      results = [Completion::UserContent.tool_result("tc1", "result1")]
      item = MultiTurnStreamItem(Crig::PromptResponse).tool_execution_committed(results)
      item.kind.tool_execution_committed?.should be_true
      item.tool_results.should be_truthy
      item.tool_results.not_nil!.size.should eq(1)
    end

    it "tool_execution_committed with empty results" do
      item = MultiTurnStreamItem(Crig::PromptResponse).tool_execution_committed([] of Completion::UserContent)
      item.kind.tool_execution_committed?.should be_true
      item.tool_results.should be_truthy
      item.tool_results.not_nil!.size.should eq(0)
    end

    it "regular stream_item still works" do
      content = StreamedAssistantContent(Crig::PromptResponse).text("hello")
      item = MultiTurnStreamItem(Crig::PromptResponse).stream_item(content)
      item.kind.stream_assistant_item?.should be_true
    end
  end
end
