require "../src/crig"

module Crig::Examples::Agent
  COMEDIAN_PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."

  def self.build_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(COMEDIAN_PREAMBLE)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Entertain me!") : String forall M
    agent.prompt(prompt).send
  end
end
