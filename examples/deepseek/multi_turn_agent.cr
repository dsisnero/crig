require "../../src/crig"
require "../agent_with_default_max_turns"

module Crig::Examples::DeepSeek::MultiTurnAgent
  PREAMBLE = Crig::Examples::AgentWithDefaultMaxTurns::PREAMBLE
  TOOLS    = Crig::Examples::AgentWithDefaultMaxTurns::TOOLS

  def self.build_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
    builder = client.agent(model)
      .preamble(PREAMBLE)

    TOOLS.each do |tool|
      builder = builder.tool(tool)
    end

    builder.build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String, max_turns : Int32 = 20) : String forall M
    agent.prompt(prompt).max_turns(max_turns).send
  end
end
