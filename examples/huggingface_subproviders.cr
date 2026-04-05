require "../src/crig"
require "./agent_with_huggingface"

module Crig::Examples::HuggingFaceSubproviders
  MODELS = [
    {"deepseek-ai/DeepSeek-V3", Crig::Providers::HuggingFace::SubProvider.together},
    {"meta-llama/Llama-3.1-8B-Instruct", Crig::Providers::HuggingFace::SubProvider.hf_inference},
    {"Meta-Llama-3.1-8B-Instruct", Crig::Providers::HuggingFace::SubProvider.sambanova},
    {"deepseek-v3", Crig::Providers::HuggingFace::SubProvider.fireworks},
    {"Qwen/Qwen2.5-32B-Instruct", Crig::Providers::HuggingFace::SubProvider.nebius},
  ]

  PREAMBLE = "You are a calculator here to help the user perform arithmetic operations. Use the tools provided to answer the user's question."
  PROMPT   = "Calculate 2 - 5"

  alias OperationArgs = Crig::Examples::AgentWithHuggingFace::OperationArgs
  alias Adder = Crig::Examples::AgentWithHuggingFace::Adder
  alias Subtract = Crig::Examples::AgentWithHuggingFace::Subtract

  TOOLS = [Adder.new.as(Crig::ToolDyn), Subtract.new.as(Crig::ToolDyn)]

  def self.build_client(
    api_key : String,
    subprovider : Crig::Providers::HuggingFace::SubProvider,
  ) : Crig::Providers::HuggingFace::Client
    Crig::Providers::HuggingFace::Client.builder
      .api_key(api_key)
      .subprovider(subprovider)
      .build
  end

  def self.build_partial_agent(
    client : Crig::Providers::HuggingFace::Client,
    model : String,
  ) : Crig::AgentBuilder(Crig::Providers::HuggingFace::CompletionModel)
    client.agent(model)
  end

  def self.build_tools_agent(
    client : Crig::Providers::HuggingFace::Client,
    model : String,
  ) : Crig::Agent(Crig::Providers::HuggingFace::CompletionModel)
    build_partial_agent(client, model)
      .preamble(PREAMBLE)
      .max_tokens(1024)
      .tools(TOOLS)
      .build
  end

  def self.run_prompt(agent : Crig::Agent(M), prompt : String = PROMPT) : String forall M
    agent.prompt(prompt).send
  end
end
