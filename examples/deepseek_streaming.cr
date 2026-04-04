require "../src/crig"
require "./agent_with_tools"

module Crig::Examples::DeepSeekStreaming
  BASIC_PREAMBLE      = "You are a helpful assistant. Be precise and concise."
  CALCULATOR_PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."
  PROMPT              = "When and where and what type is the next solar eclipse?"
  CALCULATOR_PROMPT   = "Calculate 2 - 5, then add 10 to the result"

  def self.build_basic_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
    client.agent(model)
      .preamble(BASIC_PREAMBLE)
      .temperature(0.5)
      .build
  end

  def self.build_calculator_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
    client.agent(model)
      .preamble(CALCULATOR_PREAMBLE)
      .max_tokens(1024)
      .tools(Crig::Examples::AgentWithTools.tools)
      .temperature(0.1) # Lower temperature for precise calculations
      .build
  end

  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    Crig.stream_to_stdout(stream, io)
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_prompt(prompt).send
  end

  def self.run_chat(agent : Crig::Agent(M), prompt : String = CALCULATOR_PROMPT, messages : Array(Crig::Completion::Message) = [] of Crig::Completion::Message) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_chat(prompt, messages).send
  end

  # Main executable code - only run when file is executed directly
  if PROGRAM_NAME == __FILE__
    begin
      # Check if DEEPSEEK_API_KEY is set
      deepseek_api_key = ENV["DEEPSEEK_API_KEY"]?

      if deepseek_api_key
        puts "Setting up DeepSeek streaming example (low-cost alternative to OpenAI):"
        puts "  - Model: DeepSeek Chat"
        puts "  - Feature: Streaming responses"
        puts "  - Cost: ~10x cheaper than GPT-4"
        puts ""

        # Create DeepSeek client
        puts "1. Setting up DeepSeek client..."
        client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
        puts "   ✓ DeepSeek client ready"

        # Example 1: Basic streaming with prompt
        puts ""
        puts "2. Example 1: Basic streaming response"
        puts "   Prompt: \"When and where and what type is the next solar eclipse?\""
        puts "=" * 60
        basic_agent = Crig::Examples::DeepSeekStreaming.build_basic_agent(client)
        stream1 = basic_agent.stream_prompt("When and where and what type is the next solar eclipse?").send
        puts "\nStreaming response:"
        puts "=" * 60
        Crig::Examples::DeepSeekStreaming.stream_to_stdout(stream1)
        puts "=" * 60

        # Example 2: Streaming with tools
        puts ""
        puts "3. Example 2: Streaming with calculator tools"
        puts "   Prompt: \"Calculate 2 - 5, then add 10 to the result\""
        puts "=" * 60
        calculator_agent = Crig::Examples::DeepSeekStreaming.build_calculator_agent(client)
        stream2 = calculator_agent.stream_prompt("Calculate 2 - 5, then add 10 to the result").send
        puts "\nStreaming response with tool calls:"
        puts "=" * 60
        Crig::Examples::DeepSeekStreaming.stream_to_stdout(stream2)
        puts "=" * 60

        # Example 3: Chat streaming with conversation history
        puts ""
        puts "4. Example 3: Streaming chat with conversation history"
        puts "   Conversation:"
        puts "   - User: What's 15 + 27?"
        puts "   - Assistant: [calculates...]"
        puts "   - User: Now multiply that by 3"
        puts "=" * 60

        # First message
        messages = [] of Crig::Completion::Message
        messages << Crig::Completion::Message.user("What's 15 + 27?")

        stream3 = calculator_agent.stream_chat("Now multiply that by 3", messages).send
        puts "\nStreaming chat response:"
        puts "=" * 60
        Crig::Examples::DeepSeekStreaming.stream_to_stdout(stream3)
        puts "=" * 60

        puts ""
        puts "Summary: DeepSeek provides streaming responses at ~10x lower cost"
        puts "than OpenAI, with support for tools and conversation history."
      else
        puts "DEEPSEEK_API_KEY not set."
        puts "This example uses DeepSeek Chat as a low-cost alternative to OpenAI for streaming responses."
        puts ""
        puts "To run this example:"
        puts "  export DEEPSEEK_API_KEY=your_deepseek_key"
        puts "  crystal run examples/deepseek_streaming.cr"
        puts ""
        puts "Note: DeepSeek API is significantly cheaper than OpenAI (~10x cheaper)."
        puts "      Get a free API key at: https://platform.deepseek.com/"
        puts ""
        puts "Streaming allows you to:"
        puts "1. See responses as they're generated (lower latency)"
        puts "2. Handle long responses without waiting for completion"
        puts "3. Implement typing indicators in chat applications"
      end
    rescue ex : Crig::Completion::CompletionError
      STDERR.puts "Error: #{ex.message}"
      STDERR.puts "This could be due to:"
      STDERR.puts "1. Invalid API key"
      STDERR.puts "2. API quota exceeded"
      puts "3. Network connectivity issues"
      exit 1
    rescue ex
      STDERR.puts "Error: #{ex.message}"
      STDERR.puts ex.backtrace.join("\n") if ENV["CRYSTAL_DEBUG"]?
      exit 1
    end
  end
end
