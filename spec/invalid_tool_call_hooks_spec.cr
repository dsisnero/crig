require "./spec_helper"

class DefaultHookProbe < Crig::PromptHook
end

class RecoveryHookProbe < Crig::PromptHook
  getter last_context : Crig::InvalidToolCallContext?
  getter last_action : Crig::InvalidToolCallHookAction?

  def initialize
    @last_context = nil
    @last_action = nil
  end

  def on_invalid_tool_call(context : Crig::InvalidToolCallContext) : Crig::InvalidToolCallHookAction
    @last_context = context
    @last_action = Crig::InvalidToolCallHookAction.retry("try again")
    @last_action.not_nil!
  end
end

describe "InvalidToolCallContext and InvalidToolCallHookAction" do
  it "default PromptHook.on_invalid_tool_call returns Fail" do
    hook = DefaultHookProbe.new
    context = Crig::InvalidToolCallContext.new(
      "bad_tool",
      ["tool_a"],
      ["tool_a"],
      [] of Crig::Completion::Message,
    )
    action = hook.on_invalid_tool_call(context)
    action.kind.fail?.should be_true
  end

  it "InvalidToolCallContext captures tool info" do
    ctx = Crig::InvalidToolCallContext.new(
      "search",
      ["search", "weather"],
      ["weather"],
      [Crig::Completion::Message.user("call search")],
      tool_call_id: "call_123",
      args: %({"q":"hi"}),
      is_streaming: true,
    )
    ctx.tool_name.should eq("search")
    ctx.available_tools.should eq(["search", "weather"])
    ctx.allowed_tools.should eq(["weather"])
    ctx.tool_call_id.should eq("call_123")
    ctx.args.should eq(%({"q":"hi"}))
    ctx.is_streaming?.should be_true
    ctx.chat_history.size.should eq(1)
  end

  it "InvalidToolCallHookAction provides all recovery variants" do
    Crig::InvalidToolCallHookAction.fail.kind.fail?.should be_true
    Crig::InvalidToolCallHookAction.retry("feedback").kind.retry?.should be_true
    Crig::InvalidToolCallHookAction.repair("fixed_name").kind.repair?.should be_true
    Crig::InvalidToolCallHookAction.skip("reason").kind.skip?.should be_true
  end

  it "custom hook receives context and returns recovery action" do
    hook = RecoveryHookProbe.new
    ctx = Crig::InvalidToolCallContext.new(
      "bad",
      ["good"],
      ["good"],
      [] of Crig::Completion::Message,
    )
    action = hook.on_invalid_tool_call(ctx)
    action.kind.retry?.should be_true
    action.feedback.should eq("try again")
    hook.last_context.not_nil!.tool_name.should eq("bad")
  end
end
