require "../src/crig"

module Crig::Examples::EnumDispatch
  record AgentConfig, name : String, preamble : String

  class Agents
    def initialize(&@prompt_proc : String -> String)
    end

    def self.new(agent : Crig::Agent(M)) forall M
      new do |prompt|
        agent.prompt(prompt).send
      end
    end

    def prompt(prompt : String) : String
      @prompt_proc.call(prompt)
    end
  end

  alias AgentFactory = Proc(AgentConfig, Agents)

  def self.anthropic_agent(config : AgentConfig) : Agents
    agent = Crig::Providers::Anthropic::Client.from_env
      .agent(Crig::Providers::Anthropic::CLAUDE_3_7_SONNET)
      .name(config.name)
      .preamble(config.preamble)
      .build

    Agents.new(agent)
  end

  def self.openai_agent(config : AgentConfig) : Agents
    agent = Crig::Providers::OpenAI::Client.from_env
      .completions_api
      .agent(Crig::Providers::OpenAI::GPT_4O)
      .name(config.name)
      .preamble(config.preamble)
      .build

    Agents.new(agent)
  end

  struct ProviderRegistry
    getter providers : Hash(String, AgentFactory)

    def initialize(@providers : Hash(String, AgentFactory) = self.class.default_providers)
    end

    def agent(provider : String, agent_config : AgentConfig) : Agents?
      @providers[provider]?.try(&.call(agent_config))
    end

    def self.default_providers : Hash(String, AgentFactory)
      {
        "anthropic" => ->EnumDispatch.anthropic_agent(AgentConfig),
        "openai"    => ->EnumDispatch.openai_agent(AgentConfig),
      }
    end
  end
end
