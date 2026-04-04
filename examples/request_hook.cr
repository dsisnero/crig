require "../src/crig"

module Crig::Examples::RequestHook
  class SessionIdHook < Crig::PromptHook
    @session_id : String

    def initialize(@session_id : String)
    end

    def on_tool_call(
      tool_name : String,
      tool_call_id : String?,
      internal_call_id : String,
      args : String,
    ) : Crig::ToolCallHookAction
      puts "[Session #{@session_id}] Calling tool: #{tool_name} with call ID: #{tool_call_id || "<no call ID provided>"} (internal: #{internal_call_id}) with args: #{args}"
      Crig::ToolCallHookAction.cont
    end

    def on_tool_result(
      tool_name : String,
      tool_call_id : String?,
      internal_call_id : String,
      args : String,
      result : String,
    ) : Crig::HookAction
      puts "[Session #{@session_id}] Tool result for #{tool_name} (args: #{args}): #{result}"
      Crig::HookAction.cont
    end

    def on_completion_call(
      prompt : Crig::Completion::Message,
      history : Array(Crig::Completion::Message),
    ) : Crig::HookAction
      prompt_text = case prompt.role
                    when Crig::Completion::Message::Role::User
                      prompt.content.to_a.map do |content|
                        case content
                        when Crig::Completion::UserContent
                          content.text.try(&.text) || ""
                        else
                          ""
                        end
                      end.join("\n")
                    when Crig::Completion::Message::Role::Assistant
                      prompt.content.to_a.map do |content|
                        case content
                        when Crig::Completion::AssistantContent
                          content.text.try(&.text) || ""
                        else
                          ""
                        end
                      end.join("\n")
                    else
                      ""
                    end

      puts "[Session #{@session_id}] Sending prompt: #{prompt_text}"
      Crig::HookAction.cont
    end

    def on_completion_response(
      prompt : Crig::Completion::Message,
      response,
    ) : Crig::HookAction
      if response.responds_to?(:choice)
        text = response.choice.to_a.map do |content|
          case content
          when Crig::Completion::AssistantContent
            content.text.try(&.text) || ""
          else
            ""
          end
        end.join(" ")
        puts "[Session #{@session_id}] Received response: #{text[0..100]}#{text.size > 100 ? "..." : ""}"
      else
        puts "[Session #{@session_id}] Received response: <received>"
      end
      Crig::HookAction.cont
    end

    # Optional: Also implement streaming hooks
    def on_text_delta(text_delta : String, aggregated_text : String) : Crig::HookAction
      puts "[Session #{@session_id}] Text delta: '#{text_delta}' (aggregated: '#{aggregated_text[0..50]}...')"
      Crig::HookAction.cont
    end

    def on_tool_call_delta(
      tool_call_id : String,
      internal_call_id : String,
      tool_name : String?,
      tool_call_delta : String,
    ) : Crig::HookAction
      puts "[Session #{@session_id}] Tool call delta for #{tool_name || "unknown"}: #{tool_call_delta}"
      Crig::HookAction.cont
    end
  end

  struct CalculatorArgs
    include JSON::Serializable

    getter operation : String
    getter x : Int32
    getter y : Int32

    def initialize(@operation : String, @x : Int32, @y : Int32)
    end
  end

  # Simple calculator tool for demonstration
  class CalculatorTool
    include Crig::Tool(CalculatorArgs, Int32)

    def name : String
      "calculator"
    end

    def description : String
      "Perform basic arithmetic operations"
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        "calculator",
        "Perform basic arithmetic operations",
        JSON.parse(%({
          "type": "object",
          "properties": {
            "operation": {
              "type": "string",
              "description": "The arithmetic operation to perform (add, subtract, multiply, divide)",
              "enum": ["add", "subtract", "multiply", "divide"]
            },
            "x": {
              "type": "number",
              "description": "The first number"
            },
            "y": {
              "type": "number",
              "description": "The second number"
            }
          },
          "required": ["operation", "x", "y"]
        }))
      )
    end

    def call_typed(args : CalculatorArgs) : Int32
      case args.operation
      when "add"
        args.x + args.y
      when "subtract"
        args.x - args.y
      when "multiply"
        args.x * args.y
      when "divide"
        if args.y == 0
          raise DivisionByZeroError.new("Cannot divide by zero")
        end
        args.x // args.y
      else
        raise ArgumentError.new("Unknown operation: #{args.operation}")
      end
    end
  end
end

begin
  puts "Setting up Request Hook example:"
  puts "  - Model: DeepSeek"
  puts "  - Feature: Prompt hooks for observability"
  puts "  - Task: Intercept and log agent execution"
  puts "  - Cost: ~$0.01 per interaction"
  puts ""

  # Check for required API key
  deepseek_api_key = ENV["DEEPSEEK_API_KEY"]?
  unless deepseek_api_key
    STDERR.puts "Error: DEEPSEEK_API_KEY not set"
    STDERR.puts "This example requires DeepSeek API key"
    exit 1
  end

  # Create DeepSeek client
  puts "1. Setting up DeepSeek client..."
  client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
  puts "   ✓ DeepSeek client ready"
  puts "   - Model: DeepSeek Chat"

  # Create agent with tools
  puts "2. Creating agent with calculator tool..."
  calculator_tool = Crig::Examples::RequestHook::CalculatorTool.new

  agent = client
    .agent(Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
    .preamble("You are a helpful assistant that can perform calculations. Use the calculator tool when needed.")
    .tool(calculator_tool)
    .build

  puts "   ✓ Agent created with calculator tool"

  # Create session hook
  puts "3. Creating session hook..."
  session_id = "session_abc123"
  hook = Crig::Examples::RequestHook::SessionIdHook.new(session_id)
  puts "   ✓ Session hook created"
  puts "   - Session ID: #{session_id}"
  puts "   - Hooks implemented:"
  puts "     • on_completion_call (logs prompts)"
  puts "     • on_completion_response (logs responses)"
  puts "     • on_tool_call (logs tool calls)"
  puts "     • on_tool_result (logs tool results)"
  puts "     • on_text_delta (logs streaming text)"
  puts "     • on_tool_call_delta (logs streaming tool calls)"

  puts ""
  puts "4. Testing hooks with different interactions:"
  puts "=" * 60

  # Test 1: Simple prompt without tools
  puts "\nTest 1: Simple prompt (no tools)"
  puts "-" * 40
  begin
    response = agent
      .prompt("Tell me a joke about programming")
      .with_hook(hook)
      .send

    puts "\nFinal response: #{response}"
  rescue ex : Crig::Completion::CompletionError
    puts "Error: #{ex.message}"
  end

  # Test 2: Prompt with tool usage
  puts "\n\nTest 2: Prompt requiring tool usage"
  puts "-" * 40
  begin
    response = agent
      .prompt("Calculate 15 * 8 for me")
      .with_hook(hook)
      .send

    puts "\nFinal response: #{response}"
  rescue ex : Crig::Completion::CompletionError
    puts "Error: #{ex.message}"
  end

  # Test 3: Streaming with hooks (simplified)
  puts "\n\nTest 3: Streaming with hooks (simplified)"
  puts "-" * 40
  begin
    puts "Starting streaming response..."
    stream = agent
      .stream_prompt("Explain quantum computing in simple terms")
      .with_hook(hook)
      .send

    # Simple stream consumption without usage parsing
    puts "\nStreaming response:"
    response_text = ""

    stream.each_item do |item|
      case item.kind
      when .text?
        if text = item.text
          print text.text
          response_text += text.text
          STDOUT.flush
        end
      when .tool_call?
        # Tool calls are handled by hooks
      when .tool_call_delta?
        # Tool call deltas are handled by hooks
      when .final?
        # Final response received
        puts "\n\nStreaming complete. Response length: #{response_text.size} characters"
        break
      else
        # Ignore other item types
      end
    end
  rescue ex : Crig::Completion::CompletionError
    puts "Error: #{ex.message}"
  rescue ex : JSON::ParseException
    puts "Note: Streaming completed (usage statistics not available in streaming mode)"
  end

  puts "=" * 60
  puts ""
  puts "Summary: This example shows prompt hooks for observability:"
  puts "1. SessionIdHook class implementing all hook methods"
  puts "2. Logging of prompts, responses, tool calls, and tool results"
  puts "3. Support for both streaming and non-streaming requests"
  puts "4. Calculator tool for demonstrating tool hooks"
  puts ""
  puts "Use cases for prompt hooks:"
  puts "• Debugging agent execution"
  puts "• Logging for audit trails"
  puts "• Monitoring tool usage"
  puts "• Implementing custom logic (rate limiting, validation, etc.)"
  puts "• Real-time observability in streaming applications"
  puts ""
  puts "Hook methods available:"
  puts "1. on_completion_call - Before sending prompt to model"
  puts "2. on_completion_response - After receiving response"
  puts "3. on_tool_call - Before invoking a tool"
  puts "4. on_tool_result - After tool returns result"
  puts "5. on_text_delta - During streaming, on each text chunk"
  puts "6. on_tool_call_delta - During streaming, on each tool call chunk"
rescue ex : KeyError
  STDERR.puts "Error: Missing API key"
  STDERR.puts "Please set DEEPSEEK_API_KEY environment variable"
  exit 1
rescue ex : Crig::Completion::CompletionError
  STDERR.puts "Completion error: #{ex.message}"
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
