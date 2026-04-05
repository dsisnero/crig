require "../src/crig"
require "./rag_dynamic_tools"

module Crig::Examples::RagDynamicToolsMultiTurn
  PREAMBLE = <<-TEXT
  You are a calculator here to help the user perform arithmetic operations.
  Use the tools provided to answer the user's question and do not do any math on your own.
  TEXT

  PROMPT = "Calculate (3 - 7) + 17"

  def self.build_agent(
    client : Crig::Providers::OpenAI::Client,
    completion_model : String = Crig::Providers::OpenAI::GPT_4,
    embedding_model_name : String = Crig::Providers::OpenAI::TEXT_EMBEDDING_ADA_002,
  ) : Crig::Agent(Crig::Providers::OpenAI::ResponsesCompletionModel)
    embedding_model = client.embedding_model(embedding_model_name)
    client.agent(completion_model)
      .preamble(PREAMBLE)
      .dynamic_tools(2, Crig::Examples::RagDynamicTools.build_index(embedding_model), Crig::Examples::RagDynamicTools.toolset)
      .build
  end

  def self.run_prompt(
    agent : Crig::Agent(M),
    prompt : String = PROMPT,
    max_turns : Int32 = 10,
  ) : String forall M
    agent.prompt(prompt).max_turns(max_turns).send
  end
end
