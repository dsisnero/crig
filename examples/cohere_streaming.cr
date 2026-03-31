require "../src/crig"

module Crig::Examples::CohereStreaming
  PREAMBLE = "Be precise and concise."
  PROMPT   = "When and where and what type is the next solar eclipse?"

  def self.build_agent(
    client : Crig::Providers::Cohere::Client,
    model : String = Crig::Providers::Cohere::COMMAND,
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
