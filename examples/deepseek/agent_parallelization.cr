require "../../src/crig"

module Crig::Examples::DeepSeek::AgentParallelization
  struct DocumentScore
    include JSON::Serializable
    getter score : Float32
    def initialize(@score : Float32); end
  end

  # Build agents with clean syntax
  def self.build_agent(client, role : String)
    client.extractor(DocumentScore, Crig::Providers::DeepSeek::DEEPSEEK_CHAT)
      .preamble("Your role is to score a user's statement on how #{role} it sounds between 0 and 1.")
      .build
  end

  # Main pipeline using clean syntax with parallel! macro
  def self.run_parallel_pipeline(
    manipulation_agent,
    depression_agent,
    intelligent_agent,
    statement : String
  ) : String
    # Clean syntax with Crig convenience methods and flat tuple destructuring
    pipeline = Crig.pipeline
      .chain(Crig.parallel!(
        Crig.passthrough,
        Crig.extract(manipulation_agent),
        Crig.extract(depression_agent),
        Crig.extract(intelligent_agent)
      ))
      .map do |(statement, manip_score, dep_score, int_score)|
        # Flat tuple - clean and readable!
        "
        Original statement: #{statement}
        Manipulation sentiment score: #{manip_score.unwrap.score}
        Depression sentiment score: #{dep_score.unwrap.score}
        Intelligence sentiment score: #{int_score.unwrap.score}
        "
      end

    pipeline.call(statement)
  end
end

# Main execution
begin
  client = Crig::Providers::DeepSeek::Client.from_env

  # Build agents
  manipulation_agent = Crig::Examples::DeepSeek::AgentParallelization.build_agent(client, "manipulative")
  depression_agent = Crig::Examples::DeepSeek::AgentParallelization.build_agent(client, "depressive")
  intelligent_agent = Crig::Examples::DeepSeek::AgentParallelization.build_agent(client, "intelligent")

  statement = "I hate swimming. The water always gets in my eyes."

  puts "=== DeepSeek Parallel Pipeline ==="
  puts "Using clean syntax with parallel! macro"
  puts

  result = Crig::Examples::DeepSeek::AgentParallelization.run_parallel_pipeline(
    manipulation_agent, depression_agent, intelligent_agent, statement
  )

  puts result
rescue ex
  STDERR.puts "Error: #{ex.message}"
  exit 1
end