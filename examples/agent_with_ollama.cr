require "../src/crig"

module Crig::Examples::AgentWithOllama
  PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."

  def self.build_client(base_url : String = Crig::Providers::Ollama::OLLAMA_API_BASE_URL) : Crig::Providers::Ollama::Client
    Crig::Providers::Ollama::Client.new(Crig::Nothing.new, base_url)
  end

  def self.build_agent(
    client : Crig::Providers::Ollama::Client,
    model : String = "qwen2.5:14b",
  ) : Crig::Agent(Crig::Providers::Ollama::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = "Entertain me!") : String forall M
    agent.prompt(prompt).send
  end
end
