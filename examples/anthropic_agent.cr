require "../src/crig"

module Crig::Examples::AnthropicAgent
  PREAMBLE = "Be precise and concise."

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
  ) : Crig::Agent(Crig::Providers::Anthropic::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "When and where and what type is the next solar eclipse?") : String forall M
    agent.prompt(prompt).send
  end
end
