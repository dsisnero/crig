require "../src/crig"

module Crig::Examples::AgentPromptChaining
  RNG_PREAMBLE = <<-TEXT
                 You are a random number generator designed to only either output a single whole integer that is 0 or 1. Only return the number.
  TEXT

  ADDER_PREAMBLE = <<-TEXT
                   You are a mathematician who adds 1000 to every number passed into the context, except if the number is 0 - in which case don't add anything. Only return the number.
  TEXT

  def self.build_rng_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(RNG_PREAMBLE)
      .build
  end

  def self.build_adder_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(ADDER_PREAMBLE)
      .build
  end

  def self.build_chain(rng_agent : Crig::Agent(M1), adder_agent : Crig::Agent(M2)) forall M1, M2
    Crig::Pipeline.new
      .prompt(rng_agent)
      .map_ok(->(x : String) { x })
      .prompt(adder_agent)
  end

  def self.default_prompt : String
    "Please generate a single whole integer that is 0 or 1"
  end

  def self.run_prompt(chain, prompt : String = default_prompt)
    chain.call(prompt)
  end
end
