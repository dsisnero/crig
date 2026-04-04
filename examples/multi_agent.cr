require "../src/crig"

module Crig::Examples::MultiAgent
  # The input that will be sent to the translator agent from the main agent
  struct TranslatorArgs
    include JSON::Serializable

    getter prompt : String

    def initialize(@prompt : String)
    end
  end

  # Define a wrapper around an agent so that it can be provided to another agent
  # as a tool
  class TranslatorTool(M)
    include Crig::Tool(TranslatorArgs, String)

    @agent : Crig::Agent(M)

    def initialize(@agent : Crig::Agent(M))
    end

    def name : String
      "translator"
    end

    def description : String
      "Translate any text to English. If already in English, fix grammar and syntax issues."
    end

    def definition(prompt : String) : Crig::Completion::ToolDefinition
      Crig::Completion::ToolDefinition.new(
        "translator",
        "Translate any text to English. If already in English, fix grammar and syntax issues.",
        JSON.parse(%({
          "type": "object",
          "properties": {
            "prompt": {
              "type": "string",
              "description": "The text to translate to English"
            }
          },
          "required": ["prompt"]
        }))
      )
    end

    def call_typed(args : TranslatorArgs) : String
      # Use the translator agent to translate the text
      response = @agent.chat(args.prompt, [] of Crig::Completion::Message)
      puts "Translated prompt: #{response}"
      response
    end
  end
end

begin
  puts "Setting up Multi-Agent System example:"
  puts "  - Model: DeepSeek"
  puts "  - Architecture: Agent-within-agent"
  puts "  - Task: Translation + assistance"
  puts "  - Method: Translator agent as tool"
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
  deepseek_client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
  model = deepseek_client.completion_model(Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
  puts "   ✓ DeepSeek client ready"
  puts "   - Model: DeepSeek Chat"

  # Create translator agent
  puts "2. Creating translator agent..."
  translator_agent = Crig::AgentBuilder.new(model)
    .preamble(<<-TEXT
      You are a translator assistant that will translate any input text into english.
      If the text is already in english, simply respond with the original text but fix any mistakes (grammar, syntax, etc.).
    TEXT
    )
    .build
  puts "   ✓ Translator agent ready"
  puts "   - Task: Translate to English / fix grammar"

  # Create translator tool
  puts "3. Creating translator tool..."
  translator_tool = Crig::Examples::MultiAgent::TranslatorTool.new(translator_agent)
  puts "   ✓ Translator tool created"
  puts "   - Tool name: translator"
  puts "   - Parameters: prompt (text to translate)"

  # Create multi-agent system
  puts "4. Creating multi-agent system..."
  multi_agent_system = Crig::AgentBuilder.new(model)
    .preamble(<<-TEXT
      You are a helpful assistant that can work with text in any language.
      When you receive input that is not in English, or contains grammatical errors
      use the translator tool first to ensure proper English, then provide your response.
      Always show both the translated text and your final response.
    TEXT
    )
    .tool(translator_tool)
    .build
  puts "   ✓ Multi-agent system ready"
  puts "   - Architecture: Main agent + translator tool"
  puts "   - Workflow: Input → Translator tool → Response"

  puts ""
  puts "5. Testing multi-agent system:"
  puts "=" * 60

  # Test cases
  test_cases = [
    "Bonjour, comment allez-vous?",
    "Hola, ¿cómo estás?",
    "Hello, how are you doing todya?",
    "こんにちは、元気ですか？",
    "I need help with my homewrk.",
  ]

  test_cases.each_with_index do |test_input, i|
    puts "\nTest #{i + 1}/#{test_cases.size}:"
    puts "Input: \"#{test_input}\""
    puts "-" * 40

    begin
      response = multi_agent_system.prompt(test_input).send
      puts "Response: #{response}"
    rescue ex : Crig::Completion::CompletionError
      puts "Error: #{ex.message}"
    end

    puts "-" * 40
  end

  puts "=" * 60
  puts ""
  puts "Summary: This example shows a multi-agent system where:"
  puts "1. A translator agent is wrapped as a tool"
  puts "2. The main agent can use the translator tool when needed"
  puts "3. Non-English or grammatically incorrect text is automatically translated/fixed"
  puts ""
  puts "Key features:"
  puts "• Agent-as-tool pattern"
  puts "• Automatic language detection (implicit)"
  puts "• Grammar correction"
  puts "• Clean separation of concerns"
  puts ""
  puts "Use cases:"
  puts "• Multilingual chatbots"
  puts "• Grammar correction systems"
  puts "• Translation pipelines"
  puts "• Multi-specialist agent systems"
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
