require "../src/crig"

module Crig::Examples::GeminiStreaming
  PREAMBLE = "Be precise and concise."
  PROMPT   = "When and where and what type is the next solar eclipse?"

  def self.generation_config : Crig::Providers::Gemini::GenerationConfig
    Crig::Providers::Gemini::GenerationConfig.new(
      thinking_config: Crig::Providers::Gemini::ThinkingConfig.new(
        include_thoughts: true,
        thinking_budget: 2048
      )
    )
  end

  def self.additional_params(
    config : Crig::Providers::Gemini::GenerationConfig = generation_config,
  ) : JSON::Any
    JSON.parse(%({"generationConfig":#{config.to_json}}))
  end

  def self.build_agent(
    client : Crig::Providers::Gemini::Client,
    model : String = Crig::Providers::Gemini::GEMINI_2_0_FLASH,
    config : Crig::Providers::Gemini::GenerationConfig = generation_config,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
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
