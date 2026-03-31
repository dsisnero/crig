require "../src/crig"
require "./agent_with_tools"

module Crig::Examples::AgentWithAgentTool
  CALCULATOR_PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."
  ASSISTANT_PREAMBLE  = "You are a helpful assistant that can solve problems. Use the tool provided to answer the user's question."

  def self.build_calculator_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(CALCULATOR_PREAMBLE)
      .max_tokens(1024)
      .tool(Crig::Examples::AgentWithTools::Adder.new)
      .tool(Crig::Examples::AgentWithTools::Subtract.new)
      .build
  end

  def self.build_agent_using_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    calculator_agent = build_calculator_agent(client, model)

    client.agent(model)
      .preamble(ASSISTANT_PREAMBLE)
      .max_tokens(1024)
      .tool(calculator_agent)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Calculate 2 - 5") : String forall M
    agent.prompt(prompt).send
  end
end
