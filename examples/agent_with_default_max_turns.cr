require "../src/crig"

module Crig::Examples::AgentWithDefaultMaxTurns
  PREAMBLE = <<-TEXT
             You are an assistant here to help the user select which tool is most appropriate to perform arithmetic operations.
             Follow these instructions closely.
             1. Consider the user's request carefully and identify the core elements of the request.
             2. Select which tool among those made available to you is appropriate given the context.
             3. This is very important: never perform the operation yourself.
  TEXT

  struct OperationArgs
    include JSON::Serializable

    getter x : Int32
    getter y : Int32

    def initialize(@x : Int32, @y : Int32)
    end
  end

  module ArithmeticTool
    private def parameters(x_description : String, y_description : String) : JSON::Any
      JSON.parse(%({
        "type":"object",
        "properties":{
          "x":{"type":"number","description":"#{x_description}"},
          "y":{"type":"number","description":"#{y_description}"}
        }
      }))
    end
  end

  struct Add
    include Crig::Tool(OperationArgs, Int32)
    include ArithmeticTool

    def name : String
      "add"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new("add", "Add x and y together", parameters("The first number to add", "The second number to add"))
    end

    def call_typed(args : OperationArgs) : Int32
      args.x + args.y
    end
  end

  struct Subtract
    include Crig::Tool(OperationArgs, Int32)
    include ArithmeticTool

    def name : String
      "subtract"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new("subtract", "Subtract y from x (i.e.: x - y)", parameters("The number to subtract from", "The number to subtract"))
    end

    def call_typed(args : OperationArgs) : Int32
      args.x - args.y
    end
  end

  struct Multiply
    include Crig::Tool(OperationArgs, Int32)
    include ArithmeticTool

    def name : String
      "multiply"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new("multiply", "Compute the product of x and y (i.e.: x * y)", parameters("The first factor in the product", "The second factor in the product"))
    end

    def call_typed(args : OperationArgs) : Int32
      args.x * args.y
    end
  end

  struct Divide
    include Crig::Tool(OperationArgs, Int32)
    include ArithmeticTool

    def name : String
      "divide"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new("divide", "Compute the Quotient of x and y (i.e.: x / y). Useful for ratios.", parameters("The Dividend of the division. The number being divided", "The Divisor of the division. The number by which the dividend is being divided"))
    end

    def call_typed(args : OperationArgs) : Int32
      args.x // args.y
    end
  end

  TOOLS = [Add.new, Subtract.new, Multiply.new, Divide.new]

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
  ) : Crig::Agent(Crig::Providers::Anthropic::CompletionModel)
    builder = client.agent(model)
      .preamble(PREAMBLE)
      .default_max_turns(20)

    TOOLS.each do |tool|
      builder = builder.tool(tool)
    end

    builder.build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String) : String forall M
    agent.prompt(prompt).send
  end
end
