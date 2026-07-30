require "../../spec_helper"

module Crig
  describe CompletionCallAction do
    it "continue stops hook processing" do
      action = CompletionCallAction.cont
      action.kind.cont?.should be_true
    end

    it "patch_request carries a RequestPatch" do
      patch = RequestPatch.new
      action = CompletionCallAction.patch_request(patch)
      action.kind.patch_request?.should be_true
      action.patch.should eq(patch)
    end

    it "stop terminates with reason" do
      action = CompletionCallAction.stop("too many turns")
      action.kind.stop?.should be_true
      action.reason.should eq("too many turns")
    end
  end

  describe ToolCallAction do
    it "continue passes through" do
      action = ToolCallAction.cont
      action.kind.cont?.should be_true
    end

    it "rewrite replaces arguments" do
      args = JSON.parse(%({"x": 42}))
      action = ToolCallAction.rewrite(args)
      action.kind.rewrite?.should be_true
      action.args.should eq(args)
    end

    it "stop terminates with reason" do
      action = ToolCallAction.stop("cancel")
      action.kind.stop?.should be_true
      action.reason.should eq("cancel")
    end
  end

  describe ToolResultAction do
    it "continue passes through" do
      action = ToolResultAction.cont
      action.kind.cont?.should be_true
    end

    it "rewrite replaces output" do
      output = Tool::ToolOutput.text("safe")
      action = ToolResultAction.rewrite(output)
      action.kind.rewrite?.should be_true
      action.output.should eq(output)
    end

    it "stop terminates with reason" do
      action = ToolResultAction.stop("redacted")
      action.kind.stop?.should be_true
      action.reason.should eq("redacted")
    end
  end

  describe InvalidToolCallAction do
    it "fail raises error" do
      action = InvalidToolCallAction.fail
      action.kind.fail?.should be_true
    end

    it "retry requests feedback" do
      action = InvalidToolCallAction.retry("use the correct tool name")
      action.kind.retry?.should be_true
      action.feedback.should eq("use the correct tool name")
    end

    it "repair suggests alternative tool" do
      action = InvalidToolCallAction.repair("other_tool")
      action.kind.repair?.should be_true
      action.tool_name.should eq("other_tool")
    end

    it "skip skips the call with reason" do
      action = InvalidToolCallAction.skip("not needed")
      action.kind.skip?.should be_true
      action.reason.should eq("not needed")
    end
  end

  describe ObservationAction do
    it "continue proceeds" do
      action = ObservationAction.cont
      action.kind.cont?.should be_true
    end

    it "stop terminates with reason" do
      action = ObservationAction.stop("observation limit")
      action.kind.stop?.should be_true
      action.reason.should eq("observation limit")
    end
  end

  describe ModelTurnAction do
    it "continue proceeds" do
      action = ModelTurnAction.cont
      action.kind.cont?.should be_true
    end

    it "retry with feedback" do
      action = ModelTurnAction.retry("provide a complete answer")
      action.kind.retry?.should be_true
      action.feedback.should eq("provide a complete answer")
    end

    it "stop terminates with reason" do
      action = ModelTurnAction.stop("response retry limit")
      action.kind.stop?.should be_true
      action.reason.should eq("response retry limit")
    end
  end
end
