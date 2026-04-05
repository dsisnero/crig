require "../src/crig"
require "./agent_with_tools"

module Crig::Examples::OllamaStreamingWithTools
  PREAMBLE = <<-TEXT
    You are a calculator here to help the user perform arithmetic
    operations. Use the tools provided to answer the user's question.
    make your answer long, so we can test the streaming functionality,
    like 20 words
  TEXT

  PROMPT = "Calculate 2 - 5"
  MODEL  = "llama3.2"

  def self.build_client(base_url : String = Crig::Providers::Ollama::OLLAMA_API_BASE_URL) : Crig::Providers::Ollama::Client
    Crig::Providers::Ollama::Client.new(Crig::Nothing.new, base_url)
  end

  def self.build_agent(
    client : Crig::Providers::Ollama::Client,
    model : String = MODEL,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .max_tokens(1024)
      .tools(Crig::Examples::AgentWithTools.tools)
      .build
  end

  def self.run_stream(agent : Crig::Agent(M), prompt : String = PROMPT) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_prompt(prompt).send
  end

  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    Crig.stream_to_stdout(stream, io)
  end
end
