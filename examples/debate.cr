require "../src/crig"

module Crig::Examples::Debate
  class Debater
    @deepseek_agent : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
    @ollama_agent : Crig::Agent(Crig::Providers::Ollama::CompletionModel)

    def initialize(position_a : String, position_b : String)
      # Check for required API keys
      deepseek_api_key = ENV["DEEPSEEK_API_KEY"]?
      unless deepseek_api_key
        STDERR.puts "Error: DEEPSEEK_API_KEY not set"
        STDERR.puts "This example requires DeepSeek API key for one side of the debate"
        exit 1
      end

      # Create clients
      deepseek_client = Crig::Providers::DeepSeek::Client.new(deepseek_api_key)
      ollama_client = Crig::Providers::Ollama::Client.new

      # Create agents with their positions
      @deepseek_agent = deepseek_client
        .agent(Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
        .preamble(position_a)
        .temperature(0.7)
        .build

      @ollama_agent = ollama_client
        .agent("llama3.2")
        .preamble(position_b)
        .temperature(0.7)
        .build
    end

    def rounds(n : Int32) : Nil
      history_a = [] of Crig::Completion::Message
      history_b = [] of Crig::Completion::Message
      last_resp_b : String? = nil

      n.times do |round|
        puts "\n🎤 Round #{round + 1}/#{n}"
        puts "=" * 60

        # DeepSeek's turn (position A)
        prompt_a = last_resp_b || "Plead your case!"

        puts "\n🤖 DeepSeek (Position A):"
        puts "-" * 40

        resp_a = @deepseek_agent.prompt(prompt_a)
          .with_history(history_a)
          .send

        puts resp_a
        puts "-" * 40

        # Ollama's turn (position B)
        puts "\n🦙 Ollama (Position B):"
        puts "-" * 40

        resp_b = @ollama_agent.prompt(resp_a)
          .with_history(history_b)
          .send

        puts resp_b
        puts "-" * 40

        last_resp_b = resp_b
      end
    end
  end
end

begin
  puts "Setting up AI Debate example:"
  puts "  - Model A: DeepSeek (cloud, low-cost)"
  puts "  - Model B: Ollama llama3.2 (free/local)"
  puts "  - Topic: Religion - useful vs harmful"
  puts "  - Rounds: 4"
  puts "  - Cost: ~$0.02 (DeepSeek only, Ollama is free)"
  puts ""

  # Create debater with positions
  puts "1. Creating debate agents..."
  position_a = <<-TEXT
    You believe that religion is a useful concept.
    This could be for security, financial, ethical, philosophical, metaphysical, religious or any kind of other reason.
    You choose what your arguments are.
    I will argue against you and you must rebuke me and try to convince me that I am wrong.
    Make your statements short and concise.
  TEXT

  position_b = <<-TEXT
    You believe that religion is a harmful concept.
    This could be for security, financial, ethical, philosophical, metaphysical, religious or any kind of other reason.
    You choose what your arguments are.
    I will argue against you and you must rebuke me and try to convince me that I am wrong.
    Make your statements short and concise.
  TEXT

  debater = Crig::Examples::Debate::Debater.new(position_a, position_b)

  puts "   ✓ Debate agents created"
  puts "   - DeepSeek: Position A (religion is useful)"
  puts "   - Ollama: Position B (religion is harmful)"
  puts "   - Temperature: 0.7 (for creative debate)"

  puts ""
  puts "2. Starting debate..."
  puts "=" * 60

  # Run the debate for 4 rounds
  debater.rounds(4)

  puts "=" * 60
  puts ""
  puts "Summary: This example shows a debate between two AI models:"
  puts "1. DeepSeek (cloud, low-cost) arguing religion is useful"
  puts "2. Ollama llama3.2 (free/local) arguing religion is harmful"
  puts ""
  puts "Key features:"
  puts "• Each model maintains its own conversation history"
  puts "• Models respond directly to each other's arguments"
  puts "• Temperature 0.7 allows for creative debate"
  puts "• Hybrid cost model: ~$0.02 total (DeepSeek only)"
  puts ""
  puts "Requirements:"
  puts "1. DeepSeek API key: export DEEPSEEK_API_KEY=your_key"
  puts "2. Ollama with llama3.2: ollama pull llama3.2"
  puts "3. Ollama running: ollama serve"
rescue ex : KeyError
  STDERR.puts "Error: Missing API key"
  STDERR.puts "Please set DEEPSEEK_API_KEY environment variable"
  exit 1
rescue ex : Socket::ConnectError
  STDERR.puts "Error: Cannot connect to Ollama at http://localhost:11434"
  STDERR.puts "Please ensure Ollama is running: ollama serve"
  STDERR.puts "And pull the llama3.2 model: ollama pull llama3.2"
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
