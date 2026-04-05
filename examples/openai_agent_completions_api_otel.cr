require "../src/crig"

module Crig::Examples::OpenAIAgentCompletionsApiOtel
  SERVICE_NAME = "rig-demo"
  PREAMBLE     = "You are a helpful assistant"
  PROMPT       = "Hello world!"

  def self.build_agent(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.completions_api
      .completion_model(model)
      .into_agent_builder
      .preamble(PREAMBLE)
      .build
  end

  def self.current_span : Crig::Span
    Crig::Span.current
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : String forall M
    agent.prompt(prompt).send
  end
end
