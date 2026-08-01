require "../spec_helper"

# Conformance validators ported from rig-agent/test_utils/model_conformance.rs.
# They assert a Crystal PromptError carries the exact upstream error shape.

module Crig
  module Conformance
    # Validate an UnknownToolCall error: expected tool name, allowed-tools set,
    # and retained assistant history containing a tool-call-bearing turn.
    def self.validate_unknown_tool_failure(
      error : Completion::PromptError,
      expected_tool : String,
      expected_allowed_tools : Array(String),
    ) : Nil
      unless error.kind.unknown_tool_call?
        raise "expected UnknownToolCall, observed #{error.kind}"
      end
      allowed = error.allowed_tools || [] of String
      history = error.chat_history || [] of Completion::Message

      history_has_call = history.any? do |message|
        message.role.assistant? && message.content.any? do |item|
          content = item.as?(Completion::AssistantContent)
          content && content.kind.tool_call?
        end
      end

      unless error.tool_name == expected_tool
        raise "tool=#{error.tool_name}, expected=#{expected_tool}"
      end
      unless allowed.sort == expected_allowed_tools.sort
        raise "allowed=#{allowed}, expected_allowed=#{expected_allowed_tools}"
      end
      raise "history_has_call=false" unless history_has_call
    end

    # Validate a PromptCancelled error: exact reason and retained assistant
    # history containing a call to the expected tool.
    def self.validate_cancelled_failure(
      error : Completion::PromptError,
      expected_reason : String,
      expected_tool : String,
    ) : Nil
      unless error.kind.prompt_cancelled?
        raise "expected PromptCancelled, observed #{error.kind}"
      end
      history = error.chat_history || [] of Completion::Message

      history_has_call = history.any? do |message|
        message.role.assistant? && message.content.any? do |item|
          content = item.as?(Completion::AssistantContent)
          if content && content.kind.tool_call?
            tool_call = content.tool_call
            tool_call && tool_call.function.name == expected_tool
          else
            false
          end
        end
      end

      unless error.reason == expected_reason
        raise "reason=#{error.reason}, expected=#{expected_reason}"
      end
      raise "history_has_call=false" unless history_has_call
    end

    # Validate a max-turns error: the exact configured budget and a retained
    # pending prompt in the history.
    def self.validate_max_turns_failure(
      error : Completion::PromptError,
      expected_max_turns : Int32,
    ) : Nil
      unless error.kind.max_turns_error?
        raise "expected MaxTurnsError, observed #{error.kind}"
      end
      unless error.max_turns == expected_max_turns
        raise "max_turns=#{error.max_turns}, expected=#{expected_max_turns}"
      end
      if error.chat_history.nil?
        raise "chat_history is nil for max-turns failure"
      end
    end

    # Validate that a sensitive raw tool result was produced but did not reach
    # the model's user-visible response after result hooks ran (upstream
    # `validate_result_redaction`).
    def self.validate_result_redaction(
      scenario : String,
      tool_produced_secret : Bool,
      visible_output : String,
      secret : String,
    ) : Nil
      secret_visible = visible_output.includes?(secret)
      unless tool_produced_secret && !visible_output.empty? && !secret_visible
        raise "produced_secret=#{tool_produced_secret}, secret_visible=#{secret_visible}, output=#{visible_output.inspect}"
      end
    end

    # Validate that a tool's rewritten arguments contain the expected fields
    # on every observed call (upstream `validate_rewritten_arguments`).
    def self.validate_rewritten_arguments(
      scenario : String,
      observations : Array(JSON::Any),
      expected_fields : JSON::Any,
    ) : Nil
      expected = expected_fields.as_h? || raise "expected rewritten fields must be a JSON object"
      raise "the rewritten tool was never invoked" if observations.empty?

      observations.each do |observation|
        actual = observation.as_h? || raise "observed rewritten arguments were not an object"
        expected.each do |key, expected_value|
          if actual[key]? != expected_value
            raise "rewritten field #{key} expected #{expected_value}, observed #{observation}"
          end
        end
      end
    end

    # Validate that forbidden protocol markers do not leak into the visible
    # output or the serialized run history (upstream `validate_protocol_hygiene`).
    def self.validate_protocol_hygiene(
      scenario : String,
      visible_output : String,
      serialized_history : String,
      forbidden_markers : Array(String),
    ) : Nil
      leaked = forbidden_markers.reject do |marker|
        !visible_output.includes?(marker) && !serialized_history.includes?(marker)
      end

      unless leaked.empty?
        raise "protocol markers leaked: #{leaked}; output=#{visible_output.inspect}, history=#{serialized_history.inspect}"
      end
    end

    # Validate a provider-neutral person extraction and that usage has values
    # (upstream `validate_extraction_fields`).
    def self.validate_extraction_fields(
      scenario : String,
      first_name : String?,
      last_name : String?,
      job : String?,
      usage : Crig::Completion::Usage,
    ) : Nil
      fields_match =
        first_name.try(&.downcase) == "ada" &&
          last_name.try(&.downcase) == "lovelace" &&
          (job.try(&.downcase).try(&.includes?("mathematician")) || false)

      usage_has_values = usage.input_tokens > 0 || usage.output_tokens > 0 || usage.total_tokens > 0

      unless fields_match && usage_has_values
        raise "first_name=#{first_name}, last_name=#{last_name}, job=#{job}, usage=#{usage}"
      end
    end

    # Decode a structured-output JSON response as T, failing with a contract
    # message (upstream `decode_structured_output`).
    def self.decode_structured_output(scenario : String, response : String, type : T.class) : T forall T
      T.from_json(response)
    rescue ex : JSON::ParseException | JSON::SerializableError
      raise "structured output did not decode: #{ex.message}; response=#{response.inspect}"
    end
  end
end
