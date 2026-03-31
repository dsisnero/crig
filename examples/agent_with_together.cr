require "../src/crig"
require "./agent_with_context"
require "./agent_with_tools"

module Crig::Examples::AgentWithTogether
  BASIC_PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."
  TOOLS_PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."

  def self.model_name : String
    Crig::Providers::Together::MIXTRAL_8X7B_INSTRUCT_V0_1
  end

  def self.build_basic_agent(
    client : Crig::Providers::Together::Client,
    model : String = model_name,
  ) : Crig::Agent(Crig::Providers::Together::CompletionModel)
    client.agent(model)
      .preamble(BASIC_PREAMBLE)
      .build
  end

  def self.build_tools_agent(
    client : Crig::Providers::Together::Client,
    model : String = model_name,
  ) : Crig::Agent(Crig::Providers::Together::CompletionModel)
    client.agent(model)
      .preamble(TOOLS_PREAMBLE)
      .tool(Crig::Examples::AgentWithTools::Adder.new)
      .build
  end

  def self.build_context_agent(
    client : Crig::Providers::Together::Client,
    model : String = model_name,
  ) : Crig::Agent(Crig::Providers::Together::CompletionModel)
    builder = client.agent(model)
    Crig::Examples::AgentWithContext::CONTEXTS.each do |context|
      builder = builder.context(context)
    end
    builder.build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String) : String forall M
    agent.prompt(prompt).send
  end
end
