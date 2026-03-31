require "../src/crig"

module Crig::Examples::GroqStreamingReasoning
  PREAMBLE = "You are a comedian here to entertain the user using humour and jokes."
  PROMPT   = "Entertain me!"

  def self.additional_params : JSON::Any
    JSON.parse(%({"reasoning_format":"parsed"}))
  end

  def self.build_agent(
    client : Crig::Providers::Groq::Client,
    model : String = Crig::Providers::Groq::DEEPSEEK_R1_DISTILL_LLAMA_70B,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .additional_params(additional_params)
      .build
  end

  def self.run_stream(agent : Crig::Agent(M), prompt : String = PROMPT) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_prompt(prompt).send
  end

  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    Crig.stream_to_stdout(stream, io)
  end
end
