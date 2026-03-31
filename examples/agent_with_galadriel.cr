require "../src/crig"

module Crig::Examples::AgentWithGaladriel
  PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."

  def self.build_agent(
    client : Crig::Providers::Galadriel::Client,
    model : String = Crig::Providers::Galadriel::GPT_4O,
  ) : Crig::Agent(Crig::Providers::Galadriel::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Entertain me!") : String forall M
    agent.prompt(prompt).send
  end
end
