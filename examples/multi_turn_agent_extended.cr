require "../src/crig"
require "./multi_turn_agent"

module Crig::Examples::MultiTurnAgentExtended
  PREAMBLE = Crig::Examples::MultiTurnAgent::PREAMBLE
  TOOLS    = Crig::Examples::MultiTurnAgent::TOOLS

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
  ) : Crig::Agent(Crig::Providers::Anthropic::CompletionModel)
    Crig::Examples::MultiTurnAgent.build_agent(client, model)
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String, max_turns : Int32 = 20) : Crig::PromptResponse forall M
    agent.prompt(prompt).max_turns(max_turns).extended_details.send
  end
end
