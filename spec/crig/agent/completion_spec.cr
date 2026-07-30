require "../../spec_helper"

module Crig
  describe "allowed_tool_names_for_choice" do
    it "returns all executable tools when tool_choice is nil" do
      result = allowed_tool_names_for_choice(
        executable_tool_names: Set{"tool_a", "tool_b"},
        tool_choice: nil,
        output_tool_name: nil,
        pre_filter_tool_names: nil,
      )
      result.should eq(Set{"tool_a", "tool_b"})
    end

    it "returns all tools when tool_choice is auto" do
      result = allowed_tool_names_for_choice(
        executable_tool_names: Set{"tool_a"},
        tool_choice: Completion::ToolChoice.auto,
        output_tool_name: nil,
        pre_filter_tool_names: nil,
      )
      result.should eq(Set{"tool_a"})
    end

    it "returns all tools when tool_choice is required" do
      result = allowed_tool_names_for_choice(
        executable_tool_names: Set{"tool_a"},
        tool_choice: Completion::ToolChoice.required,
        output_tool_name: nil,
        pre_filter_tool_names: nil,
      )
      result.should eq(Set{"tool_a"})
    end

    it "includes output_tool_name when specific choice names it" do
      result = allowed_tool_names_for_choice(
        executable_tool_names: Set{"tool_a"},
        tool_choice: Completion::ToolChoice.specific(["tool_a", "final_result"]),
        output_tool_name: "final_result",
        pre_filter_tool_names: nil,
      )
      result.should eq(Set{"tool_a", "final_result"})
    end

    it "intersects with pre_filter_tool_names" do
      result = allowed_tool_names_for_choice(
        executable_tool_names: Set{"tool_a", "tool_b", "tool_c"},
        tool_choice: nil,
        output_tool_name: nil,
        pre_filter_tool_names: Set{"tool_a", "tool_c"},
      )
      result.should eq(Set{"tool_a", "tool_c"})
    end

    it "returns specific tools when tool_choice is specific" do
      result = allowed_tool_names_for_choice(
        executable_tool_names: Set{"tool_a", "tool_b"},
        tool_choice: Completion::ToolChoice.specific(["tool_a"]),
        output_tool_name: nil,
        pre_filter_tool_names: nil,
      )
      result.should eq(Set{"tool_a"})
    end

    it "raises when tool_choice names a non-existent tool" do
      expect_raises(Completion::CompletionError) do
        allowed_tool_names_for_choice(
          executable_tool_names: Set{"tool_a"},
          tool_choice: Completion::ToolChoice.specific(["nonexistent"]),
          output_tool_name: nil,
          pre_filter_tool_names: nil,
        )
      end
    end

    it "raises when no tools are available" do
      expect_raises(Completion::CompletionError) do
        allowed_tool_names_for_choice(
          executable_tool_names: Set(String).new,
          tool_choice: Completion::ToolChoice.required,
          output_tool_name: nil,
          pre_filter_tool_names: nil,
        )
      end
    end
  end

  describe "resolve_output_mode" do
    it "returns Native when no schema" do
      Crig.resolve_output_mode(
        has_schema: false, has_executable_tools: true,
        output_tool_callable: true, provider_composes_native: false,
        requested: OutputMode::Auto,
      ).should eq(OutputMode::Native)
    end

    it "returns Auto→Tool when schema+tools+non-composing provider" do
      Crig.resolve_output_mode(
        has_schema: true, has_executable_tools: true,
        output_tool_callable: true, provider_composes_native: false,
        requested: OutputMode::Auto,
      ).should eq(OutputMode::Tool)
    end

    it "returns Auto→Native when provider composes" do
      Crig.resolve_output_mode(
        has_schema: true, has_executable_tools: true,
        output_tool_callable: true, provider_composes_native: true,
        requested: OutputMode::Auto,
      ).should eq(OutputMode::Native)
    end

    it "returns requested mode when explicitly set" do
      Crig.resolve_output_mode(
        has_schema: true, has_executable_tools: false,
        output_tool_callable: false, provider_composes_native: false,
        requested: OutputMode::Native,
      ).should eq(OutputMode::Native)
    end
  end
end
