require "../src/crig"

module Crig::Examples::OllamaStreaming
  PREAMBLE = "Be precise and concise."
  PROMPT   = "When and where and what type is the next solar eclipse?"
  MODEL    = "llama3.2"

  def self.build_client(base_url : String = Crig::Providers::Ollama::OLLAMA_API_BASE_URL) : Crig::Providers::Ollama::Client
    Crig::Providers::Ollama::Client.new(Crig::Nothing.new, base_url)
  end

  def self.build_agent(
    client : Crig::Providers::Ollama::Client,
    model : String = MODEL,
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
