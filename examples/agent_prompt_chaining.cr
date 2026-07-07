require "../src/crig"

module Crig::Examples::AgentPromptChaining
  RNG_PREAMBLE = "You are a random number generator. Return only a single whole integer that is either 0 or 1."

  ADDER_PREAMBLE = "Add 1000 to the number you receive, unless it is 0. Return only the final number."

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

  def self.default_prompt : String
    "Please generate a single whole integer that is 0 or 1"
  end
end
