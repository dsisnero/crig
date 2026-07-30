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

  private def self.active_tools_hint(active_tools_caused : Bool) : String
    if active_tools_caused
      " A per-turn `active_tools` allow-list narrowed the advertised tools this turn; set a compatible `tool_choice` in the same `RequestPatch`, or widen `active_tools`."
    else
      ""
    end
  end

  private def self.resolve_tool_choice_required(
    has_advertised_tool : Bool,
    pre_filter_tool_names : Set(String)?,
    executable_tool_names : Set(String),
  ) : Set(String)
    unless has_advertised_tool
      active_tools_caused = pre_filter_tool_names.try { |names| !names.empty? } || false
      hint = active_tools_hint(active_tools_caused)
      raise Completion::CompletionError.new("ToolChoice::Required forces the model to call a tool, but no tools are advertised this turn.#{hint}")
    end
    executable_tool_names.clone
  end

  private def self.resolve_tool_choice_specific(
    function_names : Array(String),
    executable_tool_names : Set(String),
    output_tool_name : String?,
    pre_filter_tool_names : Set(String)?,
  ) : Set(String)
    if function_names.empty?
      raise Completion::CompletionError.new("ToolChoice::Specific requires at least one function name")
    end
    requested = function_names.to_set
    missing = function_names.reject do |name|
      executable_tool_names.includes?(name) || output_tool_name == name
    end
    unless missing.empty?
      advertised = executable_tool_names.to_a + (output_tool_name ? [output_tool_name] : [] of String)
      active_tools_caused = pre_filter_tool_names.try { |names| missing.any? { |name| names.includes?(name) } } || false
      hint = active_tools_hint(active_tools_caused)
      raise Completion::CompletionError.new("ToolChoice::Specific requested tool names not advertised this turn: #{missing}. Advertised: #{advertised}.#{hint}")
    end
    requested
  end

  def self.allowed_tool_names_for_choice(
    executable_tool_names : Set(String),
    tool_choice : Completion::ToolChoice?,
    output_tool_name : String?,
    pre_filter_tool_names : Set(String)?,
  ) : Set(String)
    has_advertised_tool = !executable_tool_names.empty? || !output_tool_name.nil?

    allowed = case tool_choice
              when nil
                executable_tool_names.clone
              when Completion::ToolChoice
                if tool_choice.auto?
                  executable_tool_names.clone
                elsif tool_choice.required?
                  resolve_tool_choice_required(has_advertised_tool, pre_filter_tool_names, executable_tool_names)
                elsif tool_choice.none?
                  Set(String).new
                elsif tool_choice.specific?
                  resolve_tool_choice_specific(tool_choice.function_names, executable_tool_names, output_tool_name, pre_filter_tool_names)
                else
                  executable_tool_names.clone
                end
              else
                executable_tool_names.clone
              end

    if filter = pre_filter_tool_names
      allowed &= filter
    end

    allowed
  end
end
