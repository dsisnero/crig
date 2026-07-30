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

  struct PreparedCompletionRequest(M)
    getter builder : Completion::Request::CompletionRequestBuilder
    getter executable_tool_names : Set(String)
    getter allowed_tool_names : Set(String)
    getter output_tool_name : String?

    def initialize(
      @builder : Completion::Request::CompletionRequestBuilder,
      @executable_tool_names : Set(String),
      @allowed_tool_names : Set(String),
      @output_tool_name : String? = nil,
    )
    end

    # Build a PreparedCompletionRequest from agent and patch parameters.
    # Mirrors upstream build_prepared_completion_request.
    # ameba:disable Metrics/CyclomaticComplexity
    def self.build(
      model,
      prompt : Completion::Message,
      chat_history : Array(Completion::Message),
      preamble : String?,
      static_context : Array(Completion::Request::Document),
      temperature : Float64?,
      max_tokens : Int64?,
      additional_params : JSON::Any?,
      tool_choice : Completion::ToolChoice?,
      tool_defs : Array(Completion::ToolDefinition),
      output_schema : JSON::Any?,
      output_mode : OutputMode,
      committed_output_tool : String?,
      patch : RequestPatch?,
    ) : self
      # Apply patch overrides
      effective_preamble = patch.try(&.preamble) || preamble
      effective_temp = patch.try(&.temperature) || temperature
      effective_tokens = patch.try(&.max_tokens) || max_tokens
      effective_choice = patch.try(&.tool_choice) || tool_choice
      effective_additional = if patch_additional = patch.try(&.additional_params)
                               if additional_params
                                 Crig::JSONUtils.merge(additional_params, patch_additional)
                               else
                                 patch_additional
                               end
                             else
                               additional_params
                             end

      # Build the request builder
      builder = model.completion_request(prompt)
        .messages(chat_history)
        .tools(tool_defs)
      builder = builder.preamble(effective_preamble) if effective_preamble
      builder = builder.temperature(effective_temp) if effective_temp
      builder = builder.max_tokens(effective_tokens.to_i64) if effective_tokens
      builder = builder.tool_choice(effective_choice) if effective_choice
      builder = builder.additional_params_opt(effective_additional) if effective_additional
      builder = builder.output_schema_opt(output_schema)
      builder = builder.documents(static_context) unless static_context.empty?

      # Determine executable tool names
      executable_names = tool_defs.map(&.name).to_set

      # Pick output tool name
      output_tool_name = committed_output_tool || begin
        if output_mode.tool?
          Crig.pick_output_tool_name(executable_names)
        end
      end

      # Determine allowed tool names
      active_tools = patch.try(&.active_tools)
      pre_filter = active_tools.try(&.to_set)
      allowed = Crig.allowed_tool_names_for_choice(
        executable_names, effective_choice, output_tool_name, pre_filter)

      # Apply active_tools filter
      if active = active_tools
        allowed &= active.to_set
      end

      new(builder, executable_names, allowed, output_tool_name)
    end
  end
end
