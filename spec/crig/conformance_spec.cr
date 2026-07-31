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
  end
end
