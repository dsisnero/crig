require "../src/crig"

module Crig::Examples::MultiTurnStreaming
  struct OperationArgs
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    property x : Int32
    property y : Int32

    def initialize(@x : Int32, @y : Int32)
    end
  end

  class MathError < Exception
    def initialize(message = "Math error")
      super(message)
    end
  end

  struct Add
    include Crig::Tool(OperationArgs, Int32)

    def name : String
      "add"
    end

    def description : String
      "Add x and y together"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        "add",
        "Add x and y together",
        JSON.parse(%({
          "type": "object",
          "properties": {
            "x": {
              "type": "number",
              "description": "The first number to add"
            },
            "y": {
              "type": "number",
              "description": "The second number to add"
            }
          },
          "required": ["x", "y"]
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

    def description : String
      "Subtract y from x (i.e.: x - y)"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        "subtract",
        "Subtract y from x (i.e.: x - y)",
        JSON.parse(%({
          "type": "object",
          "properties": {
            "x": {
              "type": "number",
              "description": "The number to subtract from"
            },
            "y": {
              "type": "number",
              "description": "The number to subtract"
            }
          },
          "required": ["x", "y"]
        }))
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x - args.y
    end
  end

  struct Multiply
    include Crig::Tool(OperationArgs, Int32)

    def name : String
      "multiply"
    end

    def description : String
      "Compute the product of x and y (i.e.: x * y)"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        "multiply",
        "Compute the product of x and y (i.e.: x * y)",
        JSON.parse(%({
          "type": "object",
          "properties": {
            "x": {
              "type": "number",
              "description": "The first factor in the product"
            },
            "y": {
              "type": "number",
              "description": "The second factor in the product"
            }
          },
          "required": ["x", "y"]
        }))
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x * args.y
    end
  end

  struct Divide
    include Crig::Tool(OperationArgs, Int32)

    def name : String
      "divide"
    end

    def description : String
      "Compute the Quotient of x and y (i.e.: x / y). Useful for ratios."
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        "divide",
        "Compute the Quotient of x and y (i.e.: x / y). Useful for ratios.",
        JSON.parse(%({
          "type": "object",
          "properties": {
            "x": {
              "type": "number",
              "description": "The Dividend of the division. The number being divided"
            },
            "y": {
              "type": "number",
              "description": "The Divisor of the division. The number by which the dividend is being divided"
            }
          },
          "required": ["x", "y"]
        }))
      )
    end

    def call_typed(args : OperationArgs) : Int32
      if args.y == 0
        raise MathError.new("Division by zero")
      end
      args.x // args.y
    end
  end

  def self.build_calculator_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
  ) : Crig::Agent(Crig::Providers::Anthropic::CompletionModel)
    client.agent(model)
      .preamble(
        <<-PROMPT
        You are an assistant here to help the user select which tool is most appropriate to perform arithmetic operations.
        Follow these instructions closely.
        1. Consider the user's request carefully and identify the core elements of the request.
        2. Select which tool among those made available to you is appropriate given the context.
        3. This is very important: never perform the operation yourself.
        PROMPT
      )
      .tool(Add.new)
      .tool(Subtract.new)
      .tool(Multiply.new)
      .tool(Divide.new)
      .build
  end

  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    Crig.stream_to_stdout(stream, io)
  end

  # Main executable code - only run when file is executed directly
  if PROGRAM_NAME == __FILE__
    begin
      # Check if ANTHROPIC_API_KEY is set
      anthropic_api_key = ENV["ANTHROPIC_API_KEY"]?

      if anthropic_api_key
        puts "Setting up multi-turn streaming example:"
        puts "  - Model: Claude 3.5 Sonnet"
        puts "  - Feature: Multi-turn streaming with tools"
        puts "  - Task: Calculator with streaming responses"
        puts ""

        # Create Anthropic client
        puts "1. Setting up Anthropic client..."
        client = Crig::Providers::Anthropic::Client.new(anthropic_api_key)
        puts "   ✓ Anthropic client ready"

        # Create calculator agent
        puts "2. Creating calculator agent with tools..."
        calculator_agent = Crig::Examples::MultiTurnStreaming.build_calculator_agent(client)
        puts "   ✓ Calculator agent ready"
        puts "   Tools: add, subtract, multiply, divide"

        # Prompt the agent with multi-turn streaming
        puts ""
        puts "3. Multi-turn streaming example:"
        puts "   Prompt: \"Calculate 2 * (3 + 5) / 9 = ?. Describe the result to me.\""
        puts "   Max turns: 10"
        puts "=" * 60

        prompt = "Calculate 2 * (3 + 5) / 9 = ?. Describe the result to me."
        stream = calculator_agent.stream_prompt(prompt).multi_turn(10).send

        puts "\nStreaming response (multi-turn with tool calls):"
        puts "=" * 60
        Crig::Examples::MultiTurnStreaming.stream_to_stdout(stream)
        puts "=" * 60

        puts ""
        puts "Summary: This example shows multi-turn streaming with tool execution."
        puts "The agent can use tools across multiple turns while streaming responses."
      else
        puts "ANTHROPIC_API_KEY not set."
        puts "This example uses Anthropic Claude 3.5 Sonnet for multi-turn streaming with calculator tools."
        puts ""
        puts "To run this example:"
        puts "  export ANTHROPIC_API_KEY=your_anthropic_key"
        puts "  crystal run examples/multi_turn_streaming.cr"
        puts ""
        puts "Note: Multi-turn streaming allows the agent to:"
        puts "1. Use tools across multiple conversation turns"
        puts "2. Stream responses as they're generated"
        puts "3. Handle complex multi-step calculations"
        puts "4. Maintain conversation context across turns"
      end
    rescue ex : Crig::Completion::CompletionError
      STDERR.puts "Error: #{ex.message}"
      STDERR.puts "This could be due to:"
      STDERR.puts "1. Invalid API key"
      STDERR.puts "2. API quota exceeded"
      STDERR.puts "3. Network connectivity issues"
      exit 1
    rescue ex
      STDERR.puts "Error: #{ex.message}"
      STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
      exit 1
    end
  end
end
