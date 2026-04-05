require "../src/crig"

module Crig::Examples::GeminiVideoUnderstanding
  MODEL     = Crig::Providers::Gemini::GEMINI_2_5_PRO_EXP_03_25
  PREAMBLE  = "Be creative and concise. Answer directly and clearly."
  VIDEO_URL = "https://www.youtube.com/watch?v=emtHJIxLwEc"
  PROMPT    = "Summarize the video."

  def self.generation_config : Crig::Providers::Gemini::GenerationConfig
    Crig::Providers::Gemini::GenerationConfig.new(
      top_k: 1,
      top_p: 0.95,
      candidate_count: 1
    )
  end

  def self.additional_params(
    config : Crig::Providers::Gemini::GenerationConfig = generation_config,
  ) : JSON::Any
    JSON.parse(%({"generationConfig":#{config.to_json}}))
  end

  def self.build_agent(
    client : Crig::Providers::Gemini::Client,
    model : String = MODEL,
  ) : Crig::Agent(Crig::Providers::Gemini::CompletionModel)
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
      .additional_params(additional_params)
      .build
  end

  def self.video_prompt(url : String = VIDEO_URL, prompt : String = PROMPT) : Crig::Completion::Message
    Crig::Completion::Message.user(
      [
        Crig::Completion::UserContent.text(prompt),
        Crig::Completion::UserContent.new(
          Crig::Completion::UserContent::Kind::Video,
          video: Crig::Completion::Video.new(
            Crig::Completion::DocumentSourceKind.url(url),
            nil,
            JSON.parse(%({"video_metadata":{"fps":0.2}}))
          )
        ),
      ]
    )
  end

  def self.run_prompt(agent : Crig::Agent(M), message : Crig::Completion::Message = video_prompt) : String forall M
    agent.prompt(message).send
  end
end
