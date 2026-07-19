require "./spec_helper"

describe "InvalidToolCallContext and InvalidToolCallHookAction" do
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
end
