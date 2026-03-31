require "../src/crig"

module Crig::Examples::HuggingFaceStreaming
  PREAMBLE       = "Be precise and concise."
  PROMPT         = "When and where and what type is the next solar eclipse?"
  HF_MODEL       = "meta-llama/Meta-Llama-3.1-8B-Instruct"
  TOGETHER_MODEL = "deepseek-ai/DeepSeek-R1"

  def self.build_hf_agent(
    client : Crig::Providers::HuggingFace::Client,
    model : String = HF_MODEL,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
      .build
  end

  def self.build_together_client(api_key : String) : Crig::Providers::HuggingFace::Client
    Crig::Providers::HuggingFace::Client.builder
      .api_key(api_key)
      .subprovider(Crig::Providers::HuggingFace::SubProvider.together)
      .build
  end

  def self.build_together_agent(
    client : Crig::Providers::HuggingFace::Client,
    model : String = TOGETHER_MODEL,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
      .build
  end

  def self.run_stream(agent : Crig::Agent(M), prompt : String = PROMPT) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_prompt(prompt).send
  end

  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    Crig.stream_to_stdout(stream, io)
  end
end
