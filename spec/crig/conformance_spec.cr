require "../spec_helper"

def conformance_tool_call_content(id : String, name : String) : Crig::Completion::AssistantContent
  Crig::Completion::AssistantContent.tool_call(id, name, JSON.parse(%({"x":1})))
end

def completion_tool_call_with_call_id(id : String, call_id : String, name : String) : Crig::Completion::AssistantContent
  Crig::Completion::AssistantContent.tool_call_with_call_id(id, call_id, name, JSON.parse(%({"x":1})))
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

    it "decodes a structured output response" do
      result = Conformance.decode_structured_output("decode", %({"city":"NYC","temperature":72}), ConformanceWeather)

      result.city.should eq("NYC")
      result.temperature.should eq(72)
    end

    it "rejects an undecodable structured output response" do
      expect_raises(Exception, /structured output did not decode/) do
        Conformance.decode_structured_output("decode", "not-json", ConformanceWeather)
      end
    end
  end
end

# JSON::Serializable payload for decode_structured_output tests.
struct ConformanceWeather
  include JSON::Serializable

  getter city : String
  getter temperature : Int32

  def initialize(@city : String, @temperature : Int32)
  end
end

module Crig
  describe "tool correlation" do
    it "validates that every tool call has one correlated result" do
      history = [
        Completion::Message.new(
          Completion::Message::Role::Assistant,
          Crig::OneOrMany(Completion::UserContent | Completion::AssistantContent).one(
            completion_tool_call_with_call_id("call_1", "corr-1", "ping").as(Completion::UserContent | Completion::AssistantContent)
          )
        ),
        Completion::Message.user(
          Crig::Completion::UserContent.tool_result_with_call_id("call_1", "corr-1", Crig::OneOrMany(Crig::Completion::ToolResultContent).one(Crig::Completion::ToolResultContent.text("pong")))
        ),
      ]

      Conformance.validate_tool_correlation("zero_argument_tool", history)
    end

    it "rejects an uncorrelated tool result" do
      history = [
        Completion::Message.new(
          Completion::Message::Role::Assistant,
          Crig::OneOrMany(Completion::UserContent | Completion::AssistantContent).one(
            completion_tool_call_with_call_id("call_1", "corr-1", "ping").as(Completion::UserContent | Completion::AssistantContent)
          )
        ),
        Completion::Message.user(
          Crig::Completion::UserContent.tool_result_with_call_id("other", "corr-x", Crig::OneOrMany(Crig::Completion::ToolResultContent).one(Crig::Completion::ToolResultContent.text("pong")))
        ),
      ]

      expect_raises(Exception, /correlated results/) do
        Conformance.validate_tool_correlation("zero_argument_tool", history)
      end
    end
  end

  describe "tool roundtrip" do
    it "detects a call-and-result roundtrip in history" do
      history = [
        Completion::Message.new(
          Completion::Message::Role::Assistant,
          Crig::OneOrMany(Completion::UserContent | Completion::AssistantContent).one(
            completion_tool_call_with_call_id("call_1", "corr-1", "ping").as(Completion::UserContent | Completion::AssistantContent)
          )
        ),
        Completion::Message.user(
          Crig::Completion::UserContent.tool_result_with_call_id("call_1", "corr-1", Crig::OneOrMany(Crig::Completion::ToolResultContent).one(Crig::Completion::ToolResultContent.text("pong")))
        ),
      ]

      Conformance.has_tool_roundtrip(history).should be_true
    end

    it "returns false when history has no tool result" do
      history = [
        Completion::Message.new(
          Completion::Message::Role::Assistant,
          Crig::OneOrMany(Completion::UserContent | Completion::AssistantContent).one(
            completion_tool_call_with_call_id("call_1", "corr-1", "ping").as(Completion::UserContent | Completion::AssistantContent)
          )
        ),
      ]

      Conformance.has_tool_roundtrip(history).should be_false
    end
  end
end
