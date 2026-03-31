require "../src/crig"

module Crig::Examples::AnthropicThinkToolWithOtherTools
  BETA     = "token-efficient-tools-2025-02-19"
  NAME     = "Customer Service Agent"
  PREAMBLE = <<-TEXT
    You are a customer service agent for an online store.
    You have access to several tools:

    1. The 'think' tool allows you to reason through complex problems step by step.
       Use it when you need to analyze information or plan your response.

    2. The 'calculator' tool can perform basic math operations.

    3. The 'database_lookup' tool can retrieve information about store policies,
       shipping rates, and product inventory.

    When handling customer inquiries, use the 'think' tool to analyze the situation
    before responding or using other tools. This will help you provide accurate
    and helpful responses.

    IMPORTANT: Remember you have `parallel_tool_calling` enabled which means you can call
     multiple tools at once.
  TEXT
  PROMPT = "I ordered 3 units of Product A at $25 each and 2 units of Product B at $40 each. I want to return 1 unit of Product A and exchange the 2 units of Product B for Product C. How much will I get refunded, and is Product C in stock? Also, how much would it cost to ship the exchanged items with express shipping?. Lastly, how much would it cost to buy product A + 2 product B with slow shipping?"

  struct CalculatorArgs
    include JSON::Serializable

    getter expression : String

    def initialize(@expression : String)
    end
  end

  class CalculatorError < Exception
  end

  struct Calculator
    include Crig::Tool(CalculatorArgs, Float64)

    def name : String
      "calculator"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "calculator",
        "Evaluate mathematical expressions with basic operators (+, -, *, /) and parentheses. Examples of valid expressions: '2 + 2', '5 * (10 - 3)', '25 + (2 * 40)'. Does not support advanced functions like sin, cos, or logarithms.",
        JSON.parse(%({
          "type":"object",
          "properties":{
            "expression":{
              "type":"string",
              "description":"The mathematical expression to evaluate (e.g., '2 + 2', '5 * (10 - 3)', etc.)"
            }
          },
          "required":["expression"]
        }))
      )
    end

    def call_typed(args : CalculatorArgs) : Float64
      expression = args.expression
      tokens = tokenize(expression)
      parser = Parser.new(tokens)
      parser.parse_expression
    rescue ex
      raise CalculatorError.new(ex.message || "calculator error")
    end

    private def tokenize(expression : String) : Array(String)
      tokens = [] of String
      current = String::Builder.new

      expression.each_char do |char|
        if char.whitespace?
          next
        elsif char.number? || char == '.'
          current << char
        else
          unless current.empty?
            tokens << current.to_s
            current = String::Builder.new
          end

          case char
          when '+', '-', '*', '/', '(', ')'
            tokens << char.to_s
          else
            raise CalculatorError.new("Invalid character: #{char}")
          end
        end
      end

      tokens << current.to_s unless current.empty?
      tokens
    end

    private class Parser
      def initialize(@tokens : Array(String), @index : Int32 = 0)
      end

      def parse_expression : Float64
        result = parse_term
        while (token = peek) && (token == "+" || token == "-")
          op = consume
          rhs = parse_term
          result = op == "+" ? result + rhs : result - rhs
        end
        result
      end

      private def parse_term : Float64
        result = parse_factor
        while (token = peek) && (token == "*" || token == "/")
          op = consume
          rhs = parse_factor
          raise CalculatorError.new("Division by zero") if op == "/" && rhs == 0.0
          result = op == "*" ? result * rhs : result / rhs
        end
        result
      end

      private def parse_factor : Float64
        token = consume? || raise CalculatorError.new("Unexpected end of expression")
        if token == "("
          result = parse_expression
          raise CalculatorError.new("Mismatched parentheses") unless consume? == ")"
          result
        else
          token.to_f64?
            .not_nil!
        end
      rescue
        raise CalculatorError.new("Unexpected token: #{token}")
      end

      private def peek : String?
        @tokens[@index]?
      end

      private def consume : String
        consume? || raise CalculatorError.new("Unexpected end of expression")
      end

      private def consume? : String?
        token = @tokens[@index]?
        @index += 1 if token
        token
      end
    end
  end

  enum Query
    CustomerPolicy
    ShippingRates
    ProductInventory

    def self.parse(value : String) : self
      case value
      when "customer_policy"   then CustomerPolicy
      when "shipping_rates"    then ShippingRates
      when "product_inventory" then ProductInventory
      else
        raise "Unknown query: #{value}"
      end
    end

    def self.new(pull : JSON::PullParser)
      parse(pull.read_string)
    end

    def to_json(json : JSON::Builder) : Nil
      json.string(
        case self
        in .customer_policy?   then "customer_policy"
        in .shipping_rates?    then "shipping_rates"
        in .product_inventory? then "product_inventory"
        end
      )
    end
  end

  struct DatabaseLookupArgs
    include JSON::Serializable

    getter query : Query

    def initialize(@query : Query)
    end
  end

  class DatabaseLookupError < Exception
  end

  struct DatabaseLookup
    include Crig::Tool(DatabaseLookupArgs, String)

    def name : String
      "database_lookup"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      _ = prompt
      Crig::Completion::ToolDefinition.new(
        "database_lookup",
        "Look up information in a database. Only can use `customer_policy`, `shipping_rates` and `product_inventory` as valid queries.",
        JSON.parse(%({
          "type":"object",
          "properties":{
            "query":{
              "type":"string",
              "description":"The query to look up in the database"
            }
          },
          "required":["query"]
        }))
      )
    end

    def call_typed(args : DatabaseLookupArgs) : String
      case args.query
      in .customer_policy?
        "Customers can return items within 30 days with a receipt for a full refund."
      in .shipping_rates?
        "Standard shipping: $5.99, Express shipping: $15.99, Next-day shipping: $29.99"
      in .product_inventory?
        "Product A: 15 units, Product B: 8 units, Product C: Out of stock"
      end
    end
  end

  def self.build_client(api_key : String) : Crig::Providers::Anthropic::Client
    Crig::Providers::Anthropic::Client.builder
      .api_key(api_key)
      .anthropic_beta(BETA)
      .build
  end

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_7_SONNET,
  )
    client.agent(model)
      .name(NAME)
      .preamble(PREAMBLE)
      .tool(Crig::ThinkTool.new)
      .tool(Calculator.new)
      .tool(DatabaseLookup.new)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : String forall M
    history = [] of Crig::Completion::Message
    agent.prompt(prompt).with_history(history).max_turns(10).send
  end
end
