require "../src/crig"
require "./agent_with_tools"

module Crig::Examples::AgentWithMira
  BASIC_PREAMBLE      = "You are a helpful AI assistant."
  CALCULATOR_PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."

  def self.list_models(client : Crig::Providers::Mira::Client) : Array(String)
    client.list_models
  end

  def self.build_basic_agent(
    client : Crig::Providers::Mira::Client,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  ) : Crig::Agent(Crig::Providers::Mira::CompletionModel)
    client.agent(model)
      .preamble(BASIC_PREAMBLE)
      .temperature(0.7)
      .build
  end

  def self.build_calculator_agent(
    client : Crig::Providers::Mira::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
  ) : Crig::Agent(Crig::Providers::Mira::CompletionModel)
    client.agent(model)
      .preamble(CALCULATOR_PREAMBLE)
      .max_tokens(1024)
      .tool(Crig::Examples::AgentWithTools::Adder.new)
      .tool(Crig::Examples::AgentWithTools::Subtract.new)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String) : String forall M
    agent.prompt(prompt).send
  end
end
