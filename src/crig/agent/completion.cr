module Crig
  DEFAULT_OUTPUT_TOOL_NAME = "final_result"

  def self.tool_choice_permits_output_tool(tool_choice : Completion::ToolChoice?) : Bool
    case tool_choice
    when nil
      true
    when Completion::ToolChoice
      tool_choice.auto? || tool_choice.required?
    else
      false
    end
  end

  def self.output_tool_callable(tool_choice : Completion::ToolChoice?, output_tool_name : String) : Bool
    if tool_choice.try(&.specific?)
      tool_choice.try(&.function_names).try(&.includes?(output_tool_name)) || false
    else
      tool_choice_permits_output_tool(tool_choice)
    end
  end

  def self.resolve_output_mode(
    has_schema : Bool,
    has_executable_tools : Bool,
    output_tool_callable : Bool,
    provider_composes_native : Bool,
    requested : OutputMode,
  ) : OutputMode
    if !has_schema
      return OutputMode::Native
    end

    case requested
    in OutputMode::Native   then OutputMode::Native
    in OutputMode::Prompted then OutputMode::Prompted
    in OutputMode::Tool
      output_tool_callable ? OutputMode::Tool : OutputMode::Native
    in OutputMode::Auto
      if has_executable_tools && output_tool_callable && !provider_composes_native
        OutputMode::Tool
      else
        OutputMode::Native
      end
    end
  end

  def self.pick_output_tool_name(executable_tool_names : Set(String)) : String
    name = DEFAULT_OUTPUT_TOOL_NAME
    suffix = 1_u32
    while executable_tool_names.includes?(name)
      name = "#{DEFAULT_OUTPUT_TOOL_NAME}_#{suffix}"
      suffix += 1
    end
    name
  end
end
