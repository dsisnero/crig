require "../../spec_helper"

class CountScratch
  include JSON::Serializable
  property value : Int32 = 0
end

module Crig
  describe RunId do
    it "generates and displays" do
      id = RunId.generate
      id.as_str.should_not be_empty
      id.as_str.size.should eq(21)
      id.to_s.should eq(id.as_str)
    end
  end

  describe Scratchpad do
    it "insert, get, update, remove, contains" do
      pad = Scratchpad.new
      pad.get(CountScratch).should be_nil
      pad.contains?(CountScratch).should be_false

      pad.update(CountScratch) { |c| c.value += 1 }
      pad.update(CountScratch) { |c| c.value += 1 }
      pad.get(CountScratch).not_nil!.value.should eq(2)
      pad.contains?(CountScratch).should be_true

      pad.remove(CountScratch).not_nil!.value.should eq(2)
      pad.contains?(CountScratch).should be_false
    end

    it "is shared across clones" do
      pad = Scratchpad.new
      clone = Scratchpad.new(shared: pad)
      pad.insert(7_i64)
      clone.get(Int64).should eq(7)
    end

    it "insert returns previous value" do
      pad = Scratchpad.new
      pad.insert(42_i64).should be_nil
      pad.insert(99_i64).should eq(42)
      pad.get(Int64).should eq(99)
    end
  end

  describe HookContext do
    it "reports identity and turn" do
      ctx = HookContext.new(is_streaming: true, agent_name: "test-agent")
      ctx.is_streaming?.should be_true
      ctx.agent_name.should eq("test-agent")
      ctx.turn.should eq(0)
      ctx.set_turn(3)
      ctx.turn.should eq(3)
      ctx.run_id.as_str.should_not be_empty
    end
  end

  describe RequestPatch do
    it "merge scalar last_writer_wins" do
      a = RequestPatch.new.temperature(0.1)
      b = RequestPatch.new.temperature(0.9)
      a.merge(b).temperature.should eq(0.9)
    end

    it "merge active_tools intersects" do
      a = RequestPatch.new.active_tools(["search", "add", "sub"])
      b = RequestPatch.new.active_tools(["add", "sub", "mul"])
      merged = a.merge(b)
      merged.active_tools.not_nil!.sort.should eq(["add", "sub"])
    end

    it "merge active_tools empty_intersection yields empty" do
      a = RequestPatch.new.active_tools(["search"])
      b = RequestPatch.new.active_tools(["add"])
      merged = a.merge(b)
      merged.active_tools.not_nil!.should eq([] of String)
    end

    it "merge one_sided active_tools keeps the present list" do
      a = RequestPatch.new.active_tools(["search"])
      b = RequestPatch.new
      a.merge(b).active_tools.should eq(["search"])
    end

    it "builds with all setters" do
      patch = RequestPatch.new
        .preamble("You are helpful.")
        .temperature(0.5)
        .max_tokens(512_u64)
        .tool_choice(Completion::ToolChoice.auto)

      patch.preamble.should eq("You are helpful.")
      patch.temperature.should eq(0.5)
      patch.max_tokens.should eq(512)
      patch.tool_choice.not_nil!.kind.auto?.should be_true
    end

    it "empty patch is_empty" do
      RequestPatch.new.empty?.should be_true
    end

    it "patch with field is not empty" do
      RequestPatch.new.temperature(0.1).empty?.should be_false
    end
  end

  describe Flow do
    it "constructors" do
      Flow.cont.kind.continue?.should be_true
      Flow.terminate("stop").reason.should eq("stop")
      Flow.skip("denied").reason.should eq("denied")
      Flow.fail.kind.fail?.should be_true
      Flow.retry("try again").feedback.should eq("try again")
      Flow.repair("correct_name").tool_name.should eq("correct_name")
    end

    it "rewrite_args and rewrite_result" do
      args = JSON::Any.new({"x" => JSON::Any.new(42_i64)})
      f = Flow.rewrite_args(args)
      f.args.not_nil!.as_h["x"].as_i.should eq(42)

      f2 = Flow.rewrite_result("redacted")
      f2.result.should eq("redacted")
    end

    it "patch_request" do
      patch = RequestPatch.new.temperature(0.2)
      f = Flow.patch_request(patch)
      f.patch.not_nil!.temperature.should eq(0.2)
    end
  end

  describe StepEventKind do
    it "has all variants" do
      StepEventKind::CompletionCall.should be_a(StepEventKind)
      StepEventKind::CompletionResponse.should be_a(StepEventKind)
      StepEventKind::ModelTurnFinished.should be_a(StepEventKind)
      StepEventKind::InvalidToolCall.should be_a(StepEventKind)
      StepEventKind::ToolCall.should be_a(StepEventKind)
      StepEventKind::ToolResult.should be_a(StepEventKind)
      StepEventKind::TextDelta.should be_a(StepEventKind)
      StepEventKind::ToolCallDelta.should be_a(StepEventKind)
      StepEventKind::StreamResponseFinish.should be_a(StepEventKind)
    end
  end

  describe InvalidToolCallContext do
    it "stores all fields" do
      ctx = InvalidToolCallContext.new(
        tool_name: "bad_tool",
        available_tools: ["add", "sub"],
        allowed_tools: ["add"],
        chat_history: [] of Completion::Message,
        tool_call_id: "tc1",
        args: %({"x":1}),
        is_streaming: false,
      )
      ctx.tool_name.should eq("bad_tool")
      ctx.tool_call_id.should eq("tc1")
      ctx.args.should eq(%({"x":1}))
      ctx.available_tools.should eq(["add", "sub"])
    end
  end

  describe InvalidToolCallHookAction do
    it "constructors" do
      act = InvalidToolCallHookAction.fail
      act.kind.fail?.should be_true
      InvalidToolCallHookAction.retry("feedback").feedback.should eq("feedback")
      InvalidToolCallHookAction.repair("new_name").tool_name.should eq("new_name")
      InvalidToolCallHookAction.skip("reason").reason.should eq("reason")
    end
  end
end
