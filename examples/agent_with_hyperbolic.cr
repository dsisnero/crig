require "../src/crig"

module Crig::Examples::AgentWithHyperbolic
  PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."

  def self.build_agent(
    client : Crig::Providers::Hyperbolic::Client,
    model : String = Crig::Providers::Hyperbolic::DEEPSEEK_R1,
  ) : Crig::Agent(Crig::Providers::Hyperbolic::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Entertain me!") : String forall M
    agent.prompt(prompt).send
  end
end
