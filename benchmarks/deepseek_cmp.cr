require "benchmark"
require "../src/crig"

module Crig::Benchmarks
  module DeepSeekParallel
    extend self

    AGENT_COUNT = (ENV["AGENT_COUNT"]?.try(&.to_i) || 4)
    MODEL       = ENV["BENCH_MODEL"]? || "deepseek-chat"
    PROMPTS     = [
      "What is 2+2? Answer with just the number.",
      "What is the capital of France? One word.",
      "Say 'hello' in Spanish. One word.",
      "What is 5*3? Answer with just the number.",
      "What color is the sky? One word.",
      "What is 10-7? Answer with just the number.",
      "Name the largest planet. One word.",
      "What is H2O commonly called? One word.",
    ]

    def run : Nil
      api_key = ENV["DEEPSEEK_API_KEY"]?
      abort "DEEPSEEK_API_KEY not set" unless api_key

      n = {PROMPTS.size, AGENT_COUNT}.min
      prompts = PROMPTS.first(n)

      puts "=== DeepSeek Parallel Agent Benchmark ==="
      puts "model=#{MODEL} agents=#{AGENT_COUNT} prompts_per=#{n}"
      puts

      serial_s = bench_serial(api_key, prompts)
      puts "  Serial:     #{serial_s.round(2)}s"

      concurrent_s = bench_concurrent(api_key, prompts)
      puts "  Concurrent: #{concurrent_s.round(2)}s"

      speedup = serial_s / concurrent_s
      puts
      puts "=== RESULTS ==="
      puts "  Speedup: #{speedup.round(2)}x"
    end

    private def build_agent(api_key : String)
      client = Crig::Providers::DeepSeek::Client.builder.api_key(api_key).build
      client.agent(MODEL)
        .preamble("You are a helpful assistant. Answer concisely.")
        .build
    end

    private def bench_serial(api_key : String, prompts : Array(String)) : Float64
      total = 0
      started = Time.instant

      AGENT_COUNT.times do |i|
        agent = build_agent(api_key)
        prompts.each do |p|
          begin
            agent.prompt(p).send
            total += 1
          rescue ex
            STDERR.puts "  [s #{i}] err: #{ex.message.try(&.[0..50]) || ex.class}"
          end
        end
      end

      (Time.instant - started).total_seconds
    end

    private def bench_concurrent(api_key : String, prompts : Array(String)) : Float64
      channel = Channel(Float64).new(AGENT_COUNT)

      started = Time.instant

      AGENT_COUNT.times do |i|
        spawn do
          agent = build_agent(api_key)
          prompts.each do |p|
            begin
              agent.prompt(p).send
            rescue ex
            end
          end
          channel.send(0.0)
        rescue ex
          channel.send(0.0)
        end
      end

      AGENT_COUNT.times { channel.receive }
      (Time.instant - started).total_seconds
    end
  end
end

Crig::Benchmarks::DeepSeekParallel.run
