require "./spec_helper"

describe "PromptError::UnknownToolCall" do
  it "constructs with tool name and diagnostic info" do
    history = [Crig::Completion::Message.user("hello")]
    error = Crig::Completion::PromptError.unknown_tool_call(
      "bad_tool",
      ["tool_a", "tool_b"],
      ["tool_a"],
      history,
    )
    error.kind.unknown_tool_call?.should be_true
    error.tool_name.should eq("bad_tool")
    error.available_tools.should eq(["tool_a", "tool_b"])
    error.allowed_tools.should eq(["tool_a"])
    error.chat_history.should eq(history)
  end
end

describe "validate_tool_call_name" do
  it "accepts tool name in allowed set" do
    result = Crig::Completion.validate_tool_call_name?(
      "search",
      Set{"search", "weather"},
      Set{"search", "weather"},
      [] of Crig::Completion::Message,
    )
    result.should be_nil
  end

  it "rejects tool name not in allowed set" do
    history = [Crig::Completion::Message.user("call search")]
    error = Crig::Completion.validate_tool_call_name?(
      "search",
      Set{"search", "weather"},
      Set{"weather"},
      history,
    )
    error.should_not be_nil
    error = error.not_nil!
    error.kind.unknown_tool_call?.should be_true
    error.tool_name.should eq("search")
  end

  it "rejects tool name not in executable set" do
    error = Crig::Completion.validate_tool_call_name?(
      "missing_tool",
      Set{"search"},
      Set{"search"},
      [] of Crig::Completion::Message,
    )
    error.should_not be_nil
    error.not_nil!.tool_name.should eq("missing_tool")
  end
end
