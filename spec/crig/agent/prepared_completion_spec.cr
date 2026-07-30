require "../../spec_helper"

module Crig
  describe PreparedCompletionRequest do
    it "builds with basic parameters" do
      model = FakeCompletionModel.new
      prompt = Completion::Message.user("hello")
      result = PreparedCompletionRequest(typeof(model)).build(
        model: model,
        prompt: prompt,
        chat_history: [] of Completion::Message,
        preamble: "You are helpful",
        static_context: [] of Completion::Request::Document,
        temperature: 0.7,
        max_tokens: 1024_i64,
        additional_params: nil,
        tool_choice: nil,
        tool_defs: [] of Completion::ToolDefinition,
        output_schema: nil,
        output_mode: OutputMode::Native,
        committed_output_tool: nil,
        patch: nil,
      )
      result.executable_tool_names.empty?.should be_true
      result.allowed_tool_names.empty?.should be_true
      result.output_tool_name.should be_nil
    end

    it "includes tools in executable set" do
      model = FakeCompletionModel.new
      prompt = Completion::Message.user("hello")
      tools = [
        Completion::ToolDefinition.new("tool_a", "Tool A", JSON.parse(%({"type":"object"}))),
        Completion::ToolDefinition.new("tool_b", "Tool B", JSON.parse(%({"type":"object"}))),
      ]
      result = PreparedCompletionRequest(typeof(model)).build(
        model: model, prompt: prompt,
        chat_history: [] of Completion::Message,
        preamble: nil, static_context: [] of Completion::Request::Document,
        temperature: nil, max_tokens: nil, additional_params: nil,
        tool_choice: nil, tool_defs: tools,
        output_schema: nil, output_mode: OutputMode::Native,
        committed_output_tool: nil, patch: nil,
      )
      result.executable_tool_names.should eq(Set{"tool_a", "tool_b"})
      result.allowed_tool_names.should eq(Set{"tool_a", "tool_b"})
    end

    it "generates output_tool_name in Tool mode" do
      model = FakeCompletionModel.new
      prompt = Completion::Message.user("hello")
      result = PreparedCompletionRequest(typeof(model)).build(
        model: model, prompt: prompt,
        chat_history: [] of Completion::Message,
        preamble: nil, static_context: [] of Completion::Request::Document,
        temperature: nil, max_tokens: nil, additional_params: nil,
        tool_choice: nil, tool_defs: [] of Completion::ToolDefinition,
        output_schema: JSON.parse(%({"type":"object"})),
        output_mode: OutputMode::Tool,
        committed_output_tool: nil, patch: nil,
      )
      result.output_tool_name.should eq("final_result")
    end

    it "applies patch preamble override" do
      model = FakeCompletionModel.new
      prompt = Completion::Message.user("hello")
      patch = RequestPatch.new.preamble("patched preamble")
      result = PreparedCompletionRequest(typeof(model)).build(
        model: model, prompt: prompt,
        chat_history: [] of Completion::Message,
        preamble: "baseline preamble",
        static_context: [] of Completion::Request::Document,
        temperature: nil, max_tokens: nil, additional_params: nil,
        tool_choice: nil, tool_defs: [] of Completion::ToolDefinition,
        output_schema: nil, output_mode: OutputMode::Native,
        committed_output_tool: nil, patch: patch,
      )
      result.builder.preamble.should eq("patched preamble")
    end

    it "applies active_tools filter from patch" do
      model = FakeCompletionModel.new
      prompt = Completion::Message.user("hello")
      tools = [
        Completion::ToolDefinition.new("tool_a", "Tool A", JSON.parse(%({"type":"object"}))),
        Completion::ToolDefinition.new("tool_b", "Tool B", JSON.parse(%({"type":"object"}))),
      ]
      patch = RequestPatch.new.active_tools(["tool_a"])
      result = PreparedCompletionRequest(typeof(model)).build(
        model: model, prompt: prompt,
        chat_history: [] of Completion::Message,
        preamble: nil, static_context: [] of Completion::Request::Document,
        temperature: nil, max_tokens: nil, additional_params: nil,
        tool_choice: nil, tool_defs: tools,
        output_schema: nil, output_mode: OutputMode::Native,
        committed_output_tool: nil, patch: patch,
      )
      result.executable_tool_names.should eq(Set{"tool_a", "tool_b"})
      result.allowed_tool_names.should eq(Set{"tool_a"})
    end
  end
end
