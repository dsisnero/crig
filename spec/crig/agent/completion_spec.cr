require "../../spec_helper"

module Crig
  describe "OutputMode resolution" do
    it "without schema is always Native" do
      resolve_output_mode(
        has_schema: false,
        has_executable_tools: true,
        output_tool_callable: true,
        provider_composes_native: true,
        requested: OutputMode::Auto,
      ).should eq(OutputMode::Native)
    end

    it "explicit Native/Prompted are honored with schema" do
      resolve_output_mode(true, false, false, false, OutputMode::Native).should eq(OutputMode::Native)
      resolve_output_mode(true, false, false, false, OutputMode::Prompted).should eq(OutputMode::Prompted)
    end

    it "Tool degrades to Native when not callable" do
      resolve_output_mode(true, true, false, false, OutputMode::Tool).should eq(OutputMode::Native)
    end

    it "Tool is honored when callable" do
      resolve_output_mode(true, true, true, false, OutputMode::Tool).should eq(OutputMode::Tool)
    end

    it "Auto picks Tool when has tools and output is callable and provider doesn't compose" do
      resolve_output_mode(true, true, true, false, OutputMode::Auto).should eq(OutputMode::Tool)
    end

    it "Auto picks Native when provider composes native with tools" do
      resolve_output_mode(true, true, true, true, OutputMode::Auto).should eq(OutputMode::Native)
    end

    it "Auto picks Native without tools" do
      resolve_output_mode(true, false, true, true, OutputMode::Auto).should eq(OutputMode::Native)
    end
  end

  describe "pick_output_tool_name" do
    it "returns default when no collision" do
      pick_output_tool_name(Set(String).new).should eq("final_result")
    end

    it "avoids collision with real tools" do
      tools = Set{"final_result"}
      pick_output_tool_name(tools).should eq("final_result_1")
    end

    it "increments suffix for multiple collisions" do
      tools = Set{"final_result", "final_result_1"}
      pick_output_tool_name(tools).should eq("final_result_2")
    end
  end

  describe "tool_choice_permits_output_tool" do
    it "permits for nil, Auto, Required" do
      tool_choice_permits_output_tool(nil).should be_true
      tool_choice_permits_output_tool(Completion::ToolChoice.auto).should be_true
      tool_choice_permits_output_tool(Completion::ToolChoice.required).should be_true
    end

    it "forbids for None" do
      tool_choice_permits_output_tool(Completion::ToolChoice.none).should be_false
    end
  end
end
