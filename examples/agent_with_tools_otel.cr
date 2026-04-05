require "../src/crig"
require "./agent_with_tools"

module Crig::Examples::AgentWithToolsOtel
  SERVICE_NAME = "rig-demo"
  PROMPT       = "Calculate 2 - 5"

  alias OperationArgs = Crig::Examples::AgentWithTools::OperationArgs
  alias Adder = Crig::Examples::AgentWithTools::Adder
  alias Subtract = Crig::Examples::AgentWithTools::Subtract

  TOOLS = [Adder.new.as(Crig::ToolDyn), Subtract.new.as(Crig::ToolDyn)]

  def self.build_agent(
    client : Crig::Providers::OpenAI::CompletionsClient,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  ) : Crig::Agent(Crig::Providers::OpenAI::CompletionModel)
    client.agent(model)
      .preamble(Crig::Examples::AgentWithTools::PREAMBLE)
      .max_tokens(1024)
      .tools(TOOLS)
      .build
  end

  def self.current_span : Crig::Span
    Crig::Span.current
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : String forall M
    agent.prompt(prompt).send
  end
end
