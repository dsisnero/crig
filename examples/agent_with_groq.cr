require "../src/crig"

module Crig::Examples::AgentWithGroq
  PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."

  def self.build_agent(
    client : Crig::Providers::Groq::Client,
    model : String = Crig::Providers::Groq::DEEPSEEK_R1_DISTILL_LLAMA_70B,
  ) : Crig::Agent(Crig::Providers::Groq::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Entertain me!") : String forall M
    agent.prompt(prompt).send
  end
end
