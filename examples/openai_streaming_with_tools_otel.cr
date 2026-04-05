require "../src/crig"
require "./openai_streaming_with_tools"

module Crig::Examples::OpenAIStreamingWithToolsOtel
  SERVICE_NAME = "rig-demo"

  def self.build_agent(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4O,
  )
    client.agent(model)
      .preamble(Crig::Examples::OpenAIStreamingWithTools::PREAMBLE)
      .max_tokens(1024)
      .tools(Crig::Examples::AgentWithTools.tools)
      .name("Bob")
      .build
  end

  def self.current_span : Crig::Span
    Crig::Span.current
  end

  def self.run_stream(
    agent : Crig::Agent(M),
    prompt : String = Crig::Examples::OpenAIStreamingWithTools::PROMPT,
  ) forall M
    agent.stream_prompt(prompt).send
  end

  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    Crig.stream_to_stdout(stream, io)
  end
end
