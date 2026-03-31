require "../src/crig"

module Crig::Examples::AgentWithMoonshot
  BASIC_PREAMBLE   = "You are a comedian here to entertain the user using humour and jokes."
  CONTEXT_PREAMBLE = "Definition of a *glarb-glarb*: A glarb-glarb is an ancient tool used by the ancestors of the inhabitants of planet Jiro to farm the land."

  def self.partial_agent(
    client : Crig::Providers::Moonshot::Client,
    model : String = Crig::Providers::Moonshot::MOONSHOT_CHAT,
  ) : Crig::AgentBuilder(Crig::Providers::Moonshot::CompletionModel)
    client.agent(model)
  end

  def self.build_basic_agent(
    client : Crig::Providers::Moonshot::Client,
    model : String = Crig::Providers::Moonshot::MOONSHOT_CHAT,
  ) : Crig::Agent(Crig::Providers::Moonshot::CompletionModel)
    partial_agent(client, model)
      .preamble(BASIC_PREAMBLE)
      .temperature(0.5)
      .max_tokens(1024)
      .build
  end

  def self.build_context_agent(
    client : Crig::Providers::Moonshot::Client,
    model : String = Crig::Providers::Moonshot::MOONSHOT_CHAT,
  ) : Crig::Agent(Crig::Providers::Moonshot::CompletionModel)
    client.agent(model)
      .preamble(CONTEXT_PREAMBLE)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String) : String forall M
    agent.prompt(prompt).send
  end
end
