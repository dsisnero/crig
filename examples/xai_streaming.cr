require "../src/crig"

module Crig::Examples::XaiStreaming
  def self.run_prompt(client : Crig::Providers::DeepSeek::Client, prompt : String) : String
    agent = client
      .agent(Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
      .preamble("Be precise and concise.")
      .temperature(0.5)
      .build

    response = agent.prompt(prompt).send
    response.to_s
  end

  def self.run_chat(client : Crig::Providers::DeepSeek::Client, prompt : String) : String
    agent = client
      .agent(Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
      .preamble("Be precise and concise.")
      .temperature(0.5)
      .build

    response = agent.chat(prompt).send
    response.to_s
  end
end

begin
  puts "Setting up xAI Streaming example (DeepSeek variant):"
  puts "  - Model: DeepSeek Chat"
  puts "  - Feature: Streaming responses"
  puts "  - Task: Stream solar eclipse information"
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
  puts "   - Temperature: 0.5"
  puts "   - Preamble: 'Be precise and concise.'"

  # Create streaming agent
  puts "2. Creating streaming agent..."
  agent = client
    .agent(Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
    .preamble("Be precise and concise.")
    .temperature(0.5)
    .build

  puts "   ✓ Streaming agent created"

  puts ""
  puts "3. Streaming response to prompt:"
  puts "   Prompt: 'When and where and what type is the next solar eclipse?'"
  puts "=" * 60

  # Stream the response
  stream = agent
    .stream_prompt("When and where and what type is the next solar eclipse?")
    .send

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

  puts "=" * 60
  puts ""
  puts "Summary: This example demonstrates streaming responses using DeepSeek Chat model."
  puts "Key features:"
  puts "1. Real-time token-by-token streaming"
  puts "2. Temperature control for response creativity"
  puts "3. System preamble for behavior guidance"
  puts "4. Efficient response handling for long outputs"
  puts ""
  puts "Use cases for streaming:"
  puts "• Real-time chat applications"
  puts "• Progress indicators for long responses"
  puts "• Interactive applications where immediate feedback is needed"
  puts "• Reducing perceived latency for users"
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
