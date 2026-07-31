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

    it "names active_tools in the error when the filter caused the failure" do
      error = expect_raises(Completion::CompletionError) do
        allowed_tool_names_for_choice(
          executable_tool_names: Set(String).new,
          tool_choice: Completion::ToolChoice.required,
          output_tool_name: nil,
          pre_filter_tool_names: Set{"add"},
        )
      end

      error.to_s.should contain("active_tools")
      error.to_s.should contain("RequestPatch")
    end

    it "does not blame active_tools for a plain typo" do
      error = expect_raises(Completion::CompletionError) do
        allowed_tool_names_for_choice(
          executable_tool_names: Set{"add"},
          tool_choice: Completion::ToolChoice.specific(["nonexistent"]),
          output_tool_name: nil,
          pre_filter_tool_names: Set{"add"},
        )
      end

      error.to_s.should contain("nonexistent")
      error.to_s.should_not contain("active_tools")
    end

    it "allows a Specific choice naming a filtered-out tool to name the filter" do
      error = expect_raises(Completion::CompletionError) do
        allowed_tool_names_for_choice(
          executable_tool_names: Set{"add"},
          tool_choice: Completion::ToolChoice.specific(["subtract"]),
          output_tool_name: nil,
          pre_filter_tool_names: Set{"add", "subtract"},
        )
      end

      error.to_s.should contain("subtract")
      error.to_s.should contain("active_tools")
    end

    it "allows Required when only the output tool is advertised" do
      result = allowed_tool_names_for_choice(
        executable_tool_names: Set(String).new,
        tool_choice: Completion::ToolChoice.required,
        output_tool_name: "final_result",
        pre_filter_tool_names: nil,
      )
      result.should eq(Set(String).new)
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

    it "degrades Tool to Native when the output tool is not callable" do
      Crig.resolve_output_mode(
        has_schema: true, has_executable_tools: true,
        output_tool_callable: false, provider_composes_native: false,
        requested: OutputMode::Tool,
      ).should eq(OutputMode::Native)
    end

    it "degrades Auto to Native when the output tool is not callable" do
      Crig.resolve_output_mode(
        has_schema: true, has_executable_tools: true,
        output_tool_callable: false, provider_composes_native: false,
        requested: OutputMode::Auto,
      ).should eq(OutputMode::Native)
    end

    it "keeps Prompted regardless of output-tool callability" do
      Crig.resolve_output_mode(
        has_schema: true, has_executable_tools: true,
        output_tool_callable: false, provider_composes_native: false,
        requested: OutputMode::Prompted,
      ).should eq(OutputMode::Prompted)
    end

    it "returns Auto→Native when no executable tools are present" do
      Crig.resolve_output_mode(
        has_schema: true, has_executable_tools: false,
        output_tool_callable: true, provider_composes_native: false,
        requested: OutputMode::Auto,
      ).should eq(OutputMode::Native)
    end
  end

  describe "output_tool_callable" do
    it "permits the output tool for unset, auto, and required choices" do
      Crig.output_tool_callable(nil, "final_result").should be_true
      Crig.output_tool_callable(Completion::ToolChoice.auto, "final_result").should be_true
      Crig.output_tool_callable(Completion::ToolChoice.required, "final_result").should be_true
    end

    it "permits a Specific choice that names the output tool" do
      Crig.output_tool_callable(
        Completion::ToolChoice.specific(["final_result"]),
        "final_result",
      ).should be_true
    end

    it "forbids a Specific choice that omits the output tool" do
      Crig.output_tool_callable(
        Completion::ToolChoice.specific(["search"]),
        "final_result",
      ).should be_false
    end

    it "forbids a None choice" do
      Crig.output_tool_callable(Completion::ToolChoice.none, "final_result").should be_false
    end
  end

  describe "pick_output_tool_name" do
    it "defaults when the name is unused" do
      Crig.pick_output_tool_name(Set{"add", "subtract"}).should eq("final_result")
    end

    it "avoids collision with a real tool" do
      Crig.pick_output_tool_name(Set{"final_result"}).should eq("final_result_1")
    end

    it "increments past multiple collisions" do
      Crig.pick_output_tool_name(Set{"final_result", "final_result_1"}).should eq("final_result_2")
    end
  end
end
