require "../src/crig"
require "./agent_with_tools"

module Crig::Examples::GeminiStreamingWithTools
  PREAMBLE = <<-TEXT
  You are a calculator here to help the user perform arithmetic
  operations. Use the tools provided to answer the user's question.
  make your answer long, so we can test the streaming functionality,
  like 20 words
  TEXT

  PROMPT = "Calculate 2 - 5"

  def self.generation_config : Crig::Providers::Gemini::GenerationConfig
    Crig::Providers::Gemini::GenerationConfig.new
  end

  def self.additional_params(
    config : Crig::Providers::Gemini::GenerationConfig = generation_config,
  ) : JSON::Any
    JSON.parse(%({"generationConfig":#{config.to_json}}))
  end

  def self.build_agent(
    client : Crig::Providers::Gemini::Client,
    model : String = Crig::Providers::Gemini::GEMINI_2_5_FLASH,
    config : Crig::Providers::Gemini::GenerationConfig = generation_config,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .max_tokens(1024)
      .tools(Crig::Examples::AgentWithTools.tools)
      .additional_params(additional_params(config))
      .build
  end

  def self.run_stream(agent : Crig::Agent(M), prompt : String = PROMPT) : Crig::StreamingCompletionResponse(Crig::FinalResponse) forall M
    agent.stream_prompt(prompt).send
  end

  def self.stream_to_stdout(stream : Crig::StreamingCompletionResponse(Crig::FinalResponse), io : IO = STDOUT) : Crig::FinalResponse
    Crig.stream_to_stdout(stream, io)
  end
end
