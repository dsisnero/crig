require "../../spec_helper"

module Crig
  describe "StreamToolExecutionCommitted" do
    it "carries tool results" do
      results = [Completion::UserContent.tool_result("tc1", "result1")]
      item = StreamToolExecutionCommitted.new(results)
      item.tool_results.size.should eq(1)
    end

    it "round-trips through properties" do
      results = [
        Completion::UserContent.tool_result("tc1", "out1"),
        Completion::UserContent.tool_result("tc2", "out2"),
      ]
      item = StreamToolExecutionCommitted.new(results)
      item.tool_results[0].tool_result.try(&.id).should eq("tc1")
      item.tool_results[1].tool_result.try(&.id).should eq("tc2")
    end
  end
end
