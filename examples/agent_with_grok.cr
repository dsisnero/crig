require "../src/crig"
require "./agent_with_context"
require "./agent_with_loaders"
require "./agent_with_tools"

module Crig::Examples::AgentWithGrok
  BASIC_PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."
  TOOLS_PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."

  def self.partial_agent(
    client : Crig::Providers::XAI::Client,
    model : String = Crig::Providers::XAI::GROK_3_MINI,
  ) : Crig::AgentBuilder(Crig::Providers::XAI::CompletionModel)
    client.agent(model)
  end

  def self.build_basic_agent(
    client : Crig::Providers::XAI::Client,
    model : String = Crig::Providers::XAI::GROK_3_MINI,
  ) : Crig::Agent(Crig::Providers::XAI::CompletionModel)
    partial_agent(client, model)
      .default_max_turns(32)
      .preamble(BASIC_PREAMBLE)
      .build
  end

  def self.build_tools_agent(
    client : Crig::Providers::XAI::Client,
    model : String = Crig::Providers::XAI::GROK_3_MINI,
  ) : Crig::Agent(Crig::Providers::XAI::CompletionModel)
    partial_agent(client, model)
      .preamble(TOOLS_PREAMBLE)
      .max_tokens(1024)
      .default_max_turns(32)
      .tool(Crig::Examples::AgentWithTools::Adder.new)
      .tool(Crig::Examples::AgentWithTools::Subtract.new)
      .build
  end

  def self.build_loaders_agent(
    client : Crig::Providers::XAI::Client,
    model : String = Crig::Providers::XAI::GROK_3_MINI,
    glob : String = "vendor/rig/rig/rig-core/examples/*.rs",
  ) : Crig::Agent(Crig::Providers::XAI::CompletionModel)
    builder = Crig::AgentBuilder(Crig::Providers::XAI::CompletionModel).new(client.completion_model(model))
    Crig::Examples::AgentWithLoaders.load_examples(glob).each do |path, content|
      builder = builder.context(%(Rust Example #{path.inspect}:\n#{content}))
    end
    builder.build
  end

  def self.build_context_agent(
    client : Crig::Providers::XAI::Client,
    model : String = Crig::Providers::XAI::GROK_3_MINI,
  ) : Crig::Agent(Crig::Providers::XAI::CompletionModel)
    builder = Crig::AgentBuilder(Crig::Providers::XAI::CompletionModel).new(client.completion_model(model))
    Crig::Examples::AgentWithContext::CONTEXTS.each do |context|
      builder = builder.context(context)
    end
    builder.default_max_turns(32).build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String) : String forall M
    agent.prompt(prompt).send
  end
end
