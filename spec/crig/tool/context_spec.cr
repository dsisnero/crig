require "../../spec_helper"

module Crig::Tool
  describe ToolContext do
    it "separates inbound and result values" do
      context = ToolContext.new
      context.insert(42_u32)
      context.insert_result("request-1")

      context.get(UInt32).should eq(42_u32)
      context.result(String).should eq("request-1")

      dispatched = context.for_dispatch
      dispatched.get(UInt32).should eq(42_u32)
      dispatched.result(String).should be_nil
    end

    it "insert and get returns value" do
      c = ToolContext.new
      c.insert(42_u32)
      c.get(UInt32).should eq(42_u32)
    end

    it "get missing type returns nil" do
      ToolContext.new.get(UInt32).should be_nil
    end

    it "insert overwrites and returns previous" do
      c = ToolContext.new
      c.insert(1_u32)
      c.insert(2_u32).should eq(1_u32)
      c.get(UInt32).should eq(2_u32)
    end

    it "different types are independent" do
      c = ToolContext.new
      c.insert(42_u32)
      c.insert("hello")
      c.get(UInt32).should eq(42_u32)
      c.get(String).should eq("hello")
    end

    it "contains tracks types" do
      c = ToolContext.new
      c.insert(42_u32)
      c.contains?(UInt32).should be_true
      c.contains?(String).should be_false
    end

    it "remove returns value and clears entry" do
      c = ToolContext.new
      c.insert(42_u32)
      c.remove(UInt32).should eq(42_u32)
      c.contains?(UInt32).should be_false
    end

    it "remove missing type returns nil" do
      ToolContext.new.remove(UInt32).should be_nil
    end

    it "require present returns value" do
      c = ToolContext.new
      c.insert(42_u32)
      c.require(UInt32).should eq(42_u32)
    end

    it "require missing raises MissingToolContext" do
      expect_raises(MissingToolContext) do
        ToolContext.new.require(UInt32)
      end
    end

    it "result metadata round trips and requires" do
      c = ToolContext.new
      c.insert_result(7_u32)
      c.result(UInt32).should eq(7_u32)
      c.require_result(UInt32).should eq(7_u32)
      c.get(UInt32).should be_nil
    end

    it "dispatch snapshot isolates inbound and publishes only result metadata" do
      c = ToolContext.new
      c.insert(7_u32)
      c.insert_result("old")

      d = c.for_dispatch
      d.get(UInt32).should eq(7_u32)
      d.result(String).should be_nil
      d.insert(8_u32)
      d.insert_result("new")

      c.accept_dispatch_result(d)
      c.get(UInt32).should eq(7_u32)
      c.result(String).should eq("new")
    end

    it "MissingToolContext converts to ToolExecutionError" do
      missing = MissingToolContext.new("UInt32")
      error = ToolExecutionError.from_error(missing)
      error.kind.should eq(ToolErrorKind::Other)
      error.message.should contain("UInt32")
    end
  end
end
