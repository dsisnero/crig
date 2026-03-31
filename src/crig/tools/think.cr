module Crig
  struct ThinkArgs
    include JSON::Serializable

    getter thought : String

    def initialize(@thought : String)
    end
  end

  class ThinkError < Exception
  end

  struct ThinkTool
    include Crig::Tool(Crig::ThinkArgs, String)

    NAME = "think"

    def name : String
      NAME
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        NAME,
        "Use the tool to think about something. It will not obtain new information or change the database, but just append the thought to the log. Use it when complex reasoning or some cache memory is needed.",
        JSON.parse(%({"type":"object","properties":{"thought":{"type":"string","description":"A thought to think about."}},"required":["thought"]})),
      )
    end

    def call_typed(args : Crig::ThinkArgs) : String
      args.thought
    end
  end
end
