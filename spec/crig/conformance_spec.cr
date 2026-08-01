require "../spec_helper"

def conformance_tool_call_content(id : String, name : String) : Crig::Completion::AssistantContent
  Crig::Completion::AssistantContent.tool_call(id, name, JSON.parse(%({"x":1})))
end

module Crig
  describe "conformance validators" do
    it "validates an UnknownToolCall failure shape" do
      error = Completion::PromptError.unknown_tool_call(
        "unknown_tool",
        ["add"],
        ["add"],
        [
          Completion::Message.assistant("hello"),
          Completion::Message.new(
            Completion::Message::Role::Assistant,
            Crig::OneOrMany(Completion::UserContent | Completion::AssistantContent).one(
              conformance_tool_call_content("call_1", "unknown_tool").as(Completion::UserContent | Completion::AssistantContent)
            )
          ),
        ],
      )

      Conformance.validate_unknown_tool_failure(error, "unknown_tool", ["add"])
    end

    it "rejects a mismatched allowed-tools set" do
      error = Completion::PromptError.unknown_tool_call(
        "unknown_tool",
        ["add"],
        ["add"],
        [
          Completion::Message.new(
            Completion::Message::Role::Assistant,
            Crig::OneOrMany(Completion::UserContent | Completion::AssistantContent).one(
              conformance_tool_call_content("call_1", "unknown_tool").as(Completion::UserContent | Completion::AssistantContent)
            )
          ),
        ],
      )

      expect_raises(Exception, /allowed=/) do
        Conformance.validate_unknown_tool_failure(error, "unknown_tool", ["sub"])
      end
    end

    it "validates a PromptCancelled failure shape" do
      error = Completion::PromptError.prompt_cancelled(
        [
          Completion::Message.new(
            Completion::Message::Role::Assistant,
            Crig::OneOrMany(Completion::UserContent | Completion::AssistantContent).one(
              conformance_tool_call_content("call_1", "add").as(Completion::UserContent | Completion::AssistantContent)
            )
          ),
        ],
        "terminated",
      )

      Conformance.validate_cancelled_failure(error, "terminated", "add")
    end

    it "validates a MaxTurnsError failure shape" do
      error = Completion::PromptError.max_turns_exceeded(
        3,
        [Completion::Message.user("hello")],
        Completion::Message.user("hello"),
      )

      Conformance.validate_max_turns_failure(error, 3)
    end

    it "validates that a sensitive tool result did not leak into visible output" do
      Conformance.validate_result_redaction("secret_tool", true, "the answer is 42", "secret-token")
    end

    it "rejects when the secret leaked into visible output" do
      expect_raises(Exception, /secret_visible=true/) do
        Conformance.validate_result_redaction("secret_tool", true, "secret-token leaked", "secret-token")
      end
    end

    it "validates rewritten tool arguments contain the expected fields" do
      Conformance.validate_rewritten_arguments(
        "rewrite",
        [JSON.parse(%({"a":1,"b":2}))],
        JSON.parse(%({"a":1})),
      )
    end

    it "rejects rewritten arguments missing an expected field" do
      expect_raises(Exception, /rewritten field a/) do
        Conformance.validate_rewritten_arguments(
          "rewrite",
          [JSON.parse(%({"b":2}))],
          JSON.parse(%({"a":1})),
        )
      end
    end

    it "validates protocol hygiene when no markers leak" do
      Conformance.validate_protocol_hygiene("hygiene", "the answer is 42", %([{"role":"user","content":"hi"}]), ["protocol_marker"])
    end

    it "rejects protocol markers leaked into visible output" do
      expect_raises(Exception, /protocol markers leaked/) do
        Conformance.validate_protocol_hygiene("hygiene", "protocol_marker in output", "{}", ["protocol_marker"])
      end
    end

    it "validates extraction fields and usage has values" do
      usage = Crig::Completion::Usage.new(input_tokens: 5, output_tokens: 3, total_tokens: 8)
      Conformance.validate_extraction_fields("extract", "Ada", "Lovelace", "Mathematician", usage)
    end

    it "rejects extraction when usage has no values" do
      expect_raises(Exception, /usage=/) do
        Conformance.validate_extraction_fields("extract", "Ada", "Lovelace", "Mathematician", Crig::Completion::Usage.new)
      end
    end
  end
end
