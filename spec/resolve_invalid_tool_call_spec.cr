require "./spec_helper"

class FailProbe < Crig::PromptHook
end

class RetryProbe < Crig::PromptHook
  def on_invalid_tool_call(context : Crig::InvalidToolCallContext) : Crig::InvalidToolCallHookAction
    Crig::InvalidToolCallHookAction.retry("try again")
  end
end

class RepairProbe < Crig::PromptHook
  def on_invalid_tool_call(context : Crig::InvalidToolCallContext) : Crig::InvalidToolCallHookAction
    Crig::InvalidToolCallHookAction.repair("weather")
  end
end

class SkipProbe < Crig::PromptHook
  def on_invalid_tool_call(context : Crig::InvalidToolCallContext) : Crig::InvalidToolCallHookAction
    Crig::InvalidToolCallHookAction.skip("skipped")
  end
end

describe "resolve_invalid_tool_call" do
  it "returns Fail when no hook is set" do
    resolution, _ = Crig.resolve_invalid_tool_call(
      nil, "bad_tool", nil, nil, nil,
      Set{"search"}, Set{"search"}, nil, [] of Crig::Completion::Message,
    )
    resolution.fail?.should be_true
  end

  it "returns Fail when hook returns Fail" do
    hook = FailProbe.new
    resolution, _ = Crig.resolve_invalid_tool_call(
      hook, "bad_tool", nil, nil, nil,
      Set{"search"}, Set{"search"}, nil, [] of Crig::Completion::Message,
    )
    resolution.fail?.should be_true
  end

  it "returns Retry with feedback when hook returns Retry" do
    hook = RetryProbe.new
    resolution, feedback = Crig.resolve_invalid_tool_call(
      hook, "bad_tool", nil, nil, nil,
      Set{"search"}, Set{"search"}, nil, [] of Crig::Completion::Message,
    )
    resolution.retry?.should be_true
    feedback.should eq("try again")
  end

  it "returns Repair with repaired name when valid" do
    hook = RepairProbe.new
    resolution, repaired_name = Crig.resolve_invalid_tool_call(
      hook, "bad_tool", nil, nil, nil,
      Set{"search", "weather"}, Set{"search", "weather"}, nil, [] of Crig::Completion::Message,
    )
    resolution.repair?.should be_true
    repaired_name.should eq("weather")
  end

  it "returns Fail when repaired name is invalid" do
    hook = RepairProbe.new
    resolution, _ = Crig.resolve_invalid_tool_call(
      hook, "bad_tool", nil, nil, nil,
      Set{"search"}, Set{"search"}, nil, [] of Crig::Completion::Message,
    )
    resolution.fail?.should be_true
  end

  it "returns Skip when hook returns Skip" do
    hook = SkipProbe.new
    resolution, reason = Crig.resolve_invalid_tool_call(
      hook, "bad_tool", nil, nil, nil,
      Set{"search"}, Set{"search"}, nil, [] of Crig::Completion::Message,
    )
    resolution.skip?.should be_true
    reason.should eq("skipped")
  end
end
