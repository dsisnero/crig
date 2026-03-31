require "../src/crig"

module Crig::Examples::SimpleModel
  def self.build_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model).build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Who are you?") : String forall M
    agent.prompt(prompt).send
  end
end
