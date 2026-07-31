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
  end
end
