require "../../src/crig"

module Crig::Examples::DeepSeekAgentWithTools
  PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."

  # Tool argument structure
  struct OperationArgs
    include JSON::Serializable

    getter x : Int32
    getter y : Int32

    def initialize(@x : Int32, @y : Int32)
    end
  end

  # Addition tool
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

  # Subtraction tool
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

  # Multiplication tool
  struct Multiply
    include Crig::Tool(OperationArgs, Int32)

    def name : String
      "multiply"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "multiply",
        "Multiply x and y together",
        JSON.parse(%({
          "type":"object",
          "properties":{
            "x":{"type":"number","description":"The first number to multiply"},
            "y":{"type":"number","description":"The second number to multiply"}
          },
          "required":["x","y"]
        }))
      )
    end

    def call_typed(args : OperationArgs) : Int32
      args.x * args.y
    end
  end

  # Division tool
  struct Divide
    include Crig::Tool(OperationArgs, Float64)

    def name : String
      "divide"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "divide",
        "Divide x by y (i.e.: x / y). Returns a float.",
        JSON.parse(%({
          "type":"object",
          "properties":{
            "x":{"type":"number","description":"The numerator"},
            "y":{"type":"number","description":"The denominator (cannot be zero)"}
          },
          "required":["x","y"]
        }))
      )
    end

    def call_typed(args : OperationArgs) : Float64
      raise "Division by zero" if args.y == 0
      args.x.to_f / args.y.to_f
    end
  end

  # Get all tools
  def self.tools : Array(Crig::ToolDyn)
    [
      Adder.new.as(Crig::ToolDyn),
      Subtract.new.as(Crig::ToolDyn),
      Multiply.new.as(Crig::ToolDyn),
      Divide.new.as(Crig::ToolDyn),
    ]
  end

  # Build agent with DeepSeek
  def self.build_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .tools(tools)
      .max_tokens(1024)
      .temperature(0.1)  # Low temperature for precise calculations
      .build
  end

  # Run prompt with agent
  def self.run_prompt(agent : Crig::Agent(M), prompt : String) : String forall M
    agent.prompt(prompt).send
  end

  # Example prompts
  def self.example_prompts : Array(String)
    [
      "Calculate 2 - 5",
      "What is 15 + 27?",
      "Multiply 8 by 7",
      "Divide 100 by 4",
      "Calculate (10 + 5) * 3",
      "What is 50 divided by 2 plus 25?",
      "Calculate the average of 10, 20, and 30",
    ]
  end
end

# Main executable code - always run for examples
begin
  # Check if DEEPSEEK_API_KEY is set
  deepseek_api_key = ENV["DEEPSEEK_API_KEY"]?

  if deepseek_api_key
    puts "Setting up DeepSeek agent with tools (low-cost alternative to OpenAI):"
    puts "  - Model: DeepSeek Chat"
    puts "  - Tools: 4 arithmetic tools (add, subtract, multiply, divide)"
    puts "  - Cost: ~10x cheaper than GPT-4 with tools"
    puts ""

    # Create DeepSeek client
    puts "1. Setting up DeepSeek client..."
    client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
    puts "   ✓ DeepSeek client ready"

    # Create agent with tools
    puts "2. Creating calculator agent with tools..."
    agent = Crig::Examples::DeepSeekAgentWithTools.build_agent(client)
    puts "   ✓ Agent created with 4 arithmetic tools"

    # Show available tools
    puts "3. Available tools:"
    Crig::Examples::DeepSeekAgentWithTools.tools.each do |tool|
      puts "   - #{tool.name}: #{tool.definition("").description}"
    end

    # Run example prompts
    puts ""
    puts "4. Running example calculations:"
    puts "=" * 60

    Crig::Examples::DeepSeekAgentWithTools.example_prompts.each_with_index do |prompt, i|
      puts "\nExample #{i + 1}: #{prompt}"
      puts "-" * 40

      begin
        result = Crig::Examples::DeepSeekAgentWithTools.run_prompt(agent, prompt)
        puts "Result: #{result}"
      rescue ex : Crig::ToolError
        puts "Tool error: #{ex.message}"
      rescue ex
        puts "Error: #{ex.message}"
      end

      puts "-" * 40
      sleep(1.second)  # Rate limiting
    end

    # Complex example
    puts ""
    puts "5. Complex example: Multi-step calculation"
    puts "   Prompt: \"Calculate (15 + 5) * 3, then divide the result by 4\""
    puts "=" * 60

    complex_result = Crig::Examples::DeepSeekAgentWithTools.run_prompt(
      agent,
      "Calculate (15 + 5) * 3, then divide the result by 4"
    )
    puts "Result: #{complex_result}"

    puts "=" * 60
    puts ""
    puts "Summary: DeepSeek provides tool-calling capabilities at ~10x lower cost"
    puts "than OpenAI, with support for:"
    puts "1. Multiple tools in a single agent"
    puts "2. Complex multi-step calculations"
    puts "3. Error handling for invalid operations (e.g., division by zero)"
    puts "4. Precise arithmetic with low temperature setting"
    puts ""
    puts "Cost comparison:"
    puts "  - OpenAI GPT-4 with tools: ~$3.00 per 1M tokens"
    puts "  - DeepSeek with tools: ~$0.30 per 1M tokens"
    puts "  - Savings: 90% cost reduction"
  else
    puts "DEEPSEEK_API_KEY not set."
    puts "This example uses DeepSeek Chat as a low-cost alternative to OpenAI for tool-calling agents."
    puts ""
    puts "To run this example:"
    puts "  export DEEPSEEK_API_KEY=your_deepseek_key"
    puts "  crystal run examples/deepseek/agent_with_tools.cr"
    puts ""
    puts "Note: DeepSeek API is significantly cheaper than OpenAI (~10x cheaper)."
    puts "      Get a free API key at: https://platform.deepseek.com/"
    puts ""
    puts "Tool-calling allows the agent to:"
    puts "1. Perform precise calculations"
    puts "2. Access external APIs or databases"
    puts "3. Execute code or scripts"
    puts "4. Retrieve real-time information"
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