require "../src/crig"

module Crig::Examples::AgentWithContext
  CONTEXTS = [
    "Definition of a *flurbo*: A flurbo is a green alien that lives on cold planets",
    "Definition of a *glarb-glarb*: A glarb-glarb is an ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land.",
    "Definition of a *linglingdong*: A term used by inhabitants of the far side of the moon to describe humans.",
  ]

  def self.build_agent(
    client : Crig::Providers::Cohere::Client,
    model : String = Crig::Providers::Cohere::COMMAND_R,
  ) : Crig::Agent(Crig::Providers::Cohere::CompletionModel)
    builder = client.agent(model)
    CONTEXTS.each do |context|
      builder = builder.context(context)
    end
    builder.build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = %(What does "glarb-glarb" mean?)) : String forall M
    agent.prompt(prompt).send
  end
end
