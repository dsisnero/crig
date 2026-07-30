require "../../spec_helper"
require "../../../examples/request_hook"

describe Crig::Examples::RequestHook::SessionIdHook do
  it "records events via AgentHook interface" do
    hook = Crig::Examples::RequestHook::SessionIdHook.new("session1")
    ctx = Crig::HookContext.new(is_streaming: false, agent_name: "test")

    flow = hook.on_event(ctx, Crig::StepEvent.completion_call("hello", 0))
    flow.kind.continue?.should be_true
    hook.events.any?(&.includes?("[Session session1] Sending prompt: hello")).should be_true
  end

  it "records tool call events" do
    hook = Crig::Examples::RequestHook::SessionIdHook.new("session2")
    ctx = Crig::HookContext.new(is_streaming: false, agent_name: "test")

    hook.on_event(ctx, Crig::StepEvent.tool_call("add", "call_1", "internal_1", %({"x":1})))
    hook.events.any?(&.includes?("[Session session2] Calling tool: add")).should be_true
  end
end
