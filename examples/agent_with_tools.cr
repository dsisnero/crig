require "../src/crig"

module Crig::Examples::AgentWithTools
  PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."

  struct OperationArgs
    include JSON::Serializable

    getter x : Int32
    getter y : Int32

    def initialize(@x : Int32, @y : Int32)
    end
  end

  struct Adder
    include Crig::Tool(OperationArgs, Int32)

    def name : String
      "add"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "add",
        "Add x and y together",
        JSON.parse(%({
          "type":"object",
          "properties":{
            "x":{"type":"number","description":"The first number to add"},
            "y":{"type":"number","description":"The second number to add"}
          },
          "required":["x","y"]
        }))
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x + args.y
    end
  end

  struct Subtract
    include Crig::Tool(OperationArgs, Int32)

    def name : String
      "subtract"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "subtract",
        "Subtract y from x (i.e.: x - y)",
        JSON.parse(%({
          "type":"object",
          "properties":{
            "x":{"type":"number","description":"The number to subtract from"},
            "y":{"type":"number","description":"The number to subtract"}
          },
          "required":["x","y"]
        }))
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x - args.y
    end
  end

  def self.tools : Array(Crig::ToolDyn)
    [
      Adder.new.as(Crig::ToolDyn),
      Subtract.new.as(Crig::ToolDyn),
    ]
  end

  def self.build_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .tools(tools)
      .max_tokens(1024)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Calculate 2 - 5") : String forall M
    agent.prompt(prompt).send
  end
end
