require "../src/crig"
require "./agent_with_tools"

module Crig::Examples::AgentWithDeepSeek
  BASIC_PREAMBLE      = "You are a helpful assistant."
  CALCULATOR_PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."

  def self.build_basic_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
    client.agent(model)
      .preamble(BASIC_PREAMBLE)
      .build
  end

  def self.build_calculator_agent(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::Agent(Crig::Providers::DeepSeek::CompletionModel)
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
