require "crig"

module Crig::Examples::CalculatorChatbot
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

  class InitError < Exception
    def initialize(message = "Init error")
      super(message)
    end
  end

  struct Add
    include Crig::Tool

    def name : String
      "add"
    end

    def description : String
      "Add x and y together"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        name: "add",
        description: "Add x and y together",
        parameters: {
          "type" => "object",
          "properties" => {
            "x" => {
              "type" => "number",
              "description" => "The first number to add"
            },
            "y" => {
              "type" => "number",
              "description" => "The second number to add"
            }
          },
          "required" => ["x", "y"]
        }
      )
    end

    def call(args : OperationArgs) : Int32
      args.x + args.y
    end
  end

  struct Subtract
    include Crig::Tool

    def name : String
      "subtract"
    end

    def description : String
      "Subtract y from x (i.e.: x - y)"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        name: "subtract",
        description: "Subtract y from x (i.e.: x - y)",
        parameters: {
          "type" => "object",
          "properties" => {
            "x" => {
              "type" => "number",
              "description" => "The number to subtract from"
            },
            "y" => {
              "type" => "number",
              "description" => "The number to subtract"
            }
          },
          "required" => ["x", "y"]
        }
      )
    end

    def call(args : OperationArgs) : Int32
      args.x - args.y
    end
  end

  struct Multiply
    include Crig::Tool

    def name : String
      "multiply"
    end

    def description : String
      "Compute the product of x and y (i.e.: x * y)"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        name: "multiply",
        description: "Compute the product of x and y (i.e.: x * y)",
        parameters: {
          "type" => "object",
          "properties" => {
            "x" => {
              "type" => "number",
              "description" => "The first factor in the product"
            },
            "y" => {
              "type" => "number",
              "description" => "The second factor in the product"
            }
          },
          "required" => ["x", "y"]
        }
      )
    end

    def call(args : OperationArgs) : Int32
      args.x * args.y
    end
  end

  struct Divide
    include Crig::Tool

    def name : String
      "divide"
    end

    def description : String
      "Compute the Quotient of x and y (i.e.: x / y). Useful for ratios."
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        name: "divide",
        description: "Compute the Quotient of x and y (i.e.: x / y). Useful for ratios.",
        parameters: {
          "type" => "object",
          "properties" => {
            "x" => {
              "type" => "number",
              "description" => "The Dividend of the division. The number being divided"
            },
            "y" => {
              "type" => "number",
              "description" => "The Divisor of the division. The number by which the dividend is being divided"
            }
          },
          "required" => ["x", "y"]
        }
      )
    end

    def call(args : OperationArgs) : Int32
      if args.y == 0
        raise MathError.new("Division by zero")
      end
      args.x // args.y
    end
  end
# Main execution
if PROGRAM_NAME == __FILE__
  begin
    # Create DeepSeek client
    deepseek_client = Crig::Providers::DeepSeek::Client.from_env

  # Create tools
  add_tool = Crig::Examples::CalculatorChatbot::Add.new
  subtract_tool = Crig::Examples::CalculatorChatbot::Subtract.new
  multiply_tool = Crig::Examples::CalculatorChatbot::Multiply.new
  divide_tool = Crig::Examples::CalculatorChatbot::Divide.new

  # Create calculator agent with tools
  calculator_agent = deepseek_client
    .agent("deepseek-chat")
    .preamble(
      <<-PROMPT
      You are an assistant here to help the user select which tool is most appropriate to perform arithmetic operations.
      Follow these instructions closely.
      1. Consider the user's request carefully and identify the core elements of the request.
      2. Select which tool among those made available to you is appropriate given the context.
      3. This is very important: never perform the operation yourself and never give me the direct result.
      Always respond with the name of the tool that should be used and the appropriate inputs
      in the following format:
      Tool: <tool name>
      Inputs: <list of inputs>
      PROMPT
    )
    .tool(add_tool)
    .tool(subtract_tool)
    .tool(multiply_tool)
    .tool(divide_tool)
    .build

  puts "Calculator Chatbot initialized!"
  puts "Available tools: add, subtract, multiply, divide"
  puts "Enter 'quit' to exit"
  puts

  loop do
    print "> "
    user_input = gets
    break unless user_input
    user_input = user_input.strip

    break if user_input.downcase == "quit"

    unless user_input.empty?
      begin
        response = calculator_agent.prompt(user_input)
        puts "Assistant: #{response.response}"
      rescue ex
        puts "Error: #{ex.message}"
      end
      puts
    end
  end

      puts "Goodbye!"
    end
  rescue ex : KeyError
    puts "Error: DEEPSEEK_API_KEY environment variable not set"
    puts "Please set DEEPSEEK_API_KEY to your DeepSeek API key"
    exit 1
  end
end
end