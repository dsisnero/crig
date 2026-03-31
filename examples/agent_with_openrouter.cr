require "../src/crig"

module Crig::Examples::AgentWithOpenRouter
  PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."

  def self.build_agent(
    client : Crig::Providers::OpenRouter::Client,
    model : String = Crig::Providers::Gemini::GEMINI_2_5_PRO_EXP_03_25,
  ) : Crig::Agent(Crig::Providers::OpenRouter::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Entertain me!") : String forall M
    agent.prompt(prompt).send
  end
end
