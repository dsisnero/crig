require "../../spec_helper"

module Crig
  # Test helpers
  class RecordingAgentHook
    include AgentHook

    getter events : Array(String)
    getter stop_on_kind : StepEvent::Kind?

    def initialize(stop_on : StepEvent::Kind? = nil)
      @events = [] of String
      @stop_on_kind = stop_on
    end

    def on_event(ctx : HookContext, event : StepEvent) : Flow
      @events << event.kind.to_s
      if s = @stop_on_kind
        return Flow.terminate("stopped") if event.kind == s
      end
      Flow.cont
    end
  end

  class TerminateOnToolHook
    include AgentHook

    def on_event(ctx : HookContext, event : StepEvent) : Flow
      if event.tool_call?
        Flow.terminate("stop-tool-call")
      else
        Flow.cont
      end
    end
  end

  class SkipOnToolHook
    include AgentHook

    def on_event(ctx : HookContext, event : StepEvent) : Flow
      if event.tool_call?
        Flow.skip("tool skipped")
      else
        Flow.cont
      end
    end
  end

  class FailOnToolCallHook
    include AgentHook

    def on_event(ctx : HookContext, event : StepEvent) : Flow
      if event.tool_call?
        Flow.fail
      else
        Flow.cont
      end
    end
  end

  class RewriteToolCallHook
    include AgentHook

    def on_event(ctx : HookContext, event : StepEvent) : Flow
      if event.tool_call?
        Flow.rewrite_args(JSON.parse(%({"x":99})))
      else
        Flow.cont
      end
    end
  end

  class PatchRequestHook
    include AgentHook

    def on_event(ctx : HookContext, event : StepEvent) : Flow
      if event.completion_call?
        Flow.patch_request(RequestPatch.new.temperature(0.3))
      else
        Flow.cont
      end
    end
  end

  describe AgentHook do
    it "RecordingAgentHook records events in order" do
      hook = RecordingAgentHook.new
      ctx = HookContext.new(is_streaming: false)
      events = [
        StepEvent.completion_call("hello", 0),
        StepEvent.completion_response("hello", "raw", "hi"),
        StepEvent.tool_call("add", "call_1", "internal_1", %({"x":1,"y":2})),
        StepEvent.tool_result("add", "call_1", "internal_1", %({"x":1,"y":2}), "3"),
      ]
      events.each { |e| hook.on_event(ctx, e) }
      hook.events.size.should eq(4)
    end

    it "termination stops run" do
      hook = RecordingAgentHook.new(stop_on: StepEvent::Kind::ToolCall)
      ctx = HookContext.new(is_streaming: false)
      flow = hook.on_event(ctx, StepEvent.tool_call("add", "call_1", "internal_1", %({"x":1})))
      flow.kind.terminate?.should be_true
      flow.reason.should eq("stopped")
    end

    it "continue passes through" do
      hook = RecordingAgentHook.new
      ctx = HookContext.new(is_streaming: false)
      flow = hook.on_event(ctx, StepEvent.completion_call("hello", 0))
      flow.kind.continue?.should be_true
    end

    it "ToolCall returns terminate on tool_call event" do
      hook = TerminateOnToolHook.new
      ctx = HookContext.new(is_streaming: false)
      flow = hook.on_event(ctx, StepEvent.tool_call("missing", "call_1", "internal_1", "{}"))
      flow.kind.terminate?.should be_true
      flow.reason.should eq("stop-tool-call")
    end

    it "ToolCall returns skip on tool_call event" do
      hook = SkipOnToolHook.new
      ctx = HookContext.new(is_streaming: false)
      flow = hook.on_event(ctx, StepEvent.tool_call("missing", "call_1", "internal_1", "{}"))
      flow.kind.skip?.should be_true
    end

    it "ToolCall does not terminate on non-tool_call event" do
      hook = TerminateOnToolHook.new
      ctx = HookContext.new(is_streaming: false)
      flow = hook.on_event(ctx, StepEvent.completion_call("hello", 0))
      flow.kind.continue?.should be_true
    end

    it "FailOnToolCallHook returns fail on tool_call" do
      hook = FailOnToolCallHook.new
      ctx = HookContext.new(is_streaming: false)
      flow = hook.on_event(ctx, StepEvent.tool_call("missing", "call_1", "internal_1", "{}"))
      flow.kind.fail?.should be_true
    end

    it "RewriteToolCallHook returns rewrite_args on tool_call" do
      hook = RewriteToolCallHook.new
      ctx = HookContext.new(is_streaming: false)
      flow = hook.on_event(ctx, StepEvent.tool_call("add", "call_1", "internal_1", %({"x":1})))
      flow.kind.rewrite_args?.should be_true
    end

    it "PatchRequestHook returns patch_request on completion_call" do
      hook = PatchRequestHook.new
      ctx = HookContext.new(is_streaming: false)
      flow = hook.on_event(ctx, StepEvent.completion_call("hello", 0))
      flow.kind.patch_request?.should be_true
      flow.patch.not_nil!.temperature.should eq(0.3)
    end
  end
end
