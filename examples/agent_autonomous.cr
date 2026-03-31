require "../src/crig"

module Crig::Examples::AgentAutonomous
  struct Counter
    include JSON::Serializable

    # The score of the document
    getter number : UInt32

    def initialize(@number : UInt32)
    end
  end

  def self.build_extractor(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, Counter)
    client.extractor(Counter, model)
      .preamble("
        Your role is to add a random number between 1 and 64 (using only integers) to the previous number.
      ")
      .build
  end

  def self.run_autonomous_loop(
    extractor : Crig::Extractor(Crig::Providers::OpenAI::ResponsesCompletionModel, Counter),
    initial_number : UInt32 = 0,
    target_number : UInt32 = 2000,
  ) : UInt32
    number = initial_number
    interval = 1.second

    # Loop the agent and allow it to run autonomously. If it hits the target number (2000 or above)
    # we then terminate the loop and return the number
    # Note that the interval is to avoid being rate limited
    loop do
      # Prompt the agent and print the response
      counter = extractor.extract(number.to_s)
      if counter.number >= target_number
        break
      else
        number += counter.number
      end
      sleep interval
    end

    number
  end
end

# Main executable code - always run for examples
begin
  # Create OpenAI client
  client = Crig::Providers::OpenAI::Client.from_env
  extractor = Crig::Examples::AgentAutonomous.build_extractor(client)

  number = Crig::Examples::AgentAutonomous.run_autonomous_loop(extractor)

  puts "Finished with number: #{number}"
rescue ex
  STDERR.puts "Error: #{ex.message}"
  exit 1
end
