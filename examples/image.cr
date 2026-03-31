require "../src/crig"

module Crig::Examples::Image
  IMAGE_URL = "https://upload.wikimedia.org/wikipedia/commons/a/a7/Camponotus_flavomarginatus_ant.jpg"
  PREAMBLE  = "You are an image describer."

  def self.build_agent(
    client : Crig::Providers::Anthropic::Client,
    model : String = Crig::Providers::Anthropic::CLAUDE_3_5_SONNET,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
      .build
  end

  def self.image_from_base64(image_base64 : String) : Crig::Completion::Image
    Crig::Completion::Image.new(
      Crig::Completion::DocumentSourceKind.base64(image_base64),
      Crig::Completion::ImageMediaType::JPEG,
    )
  end

  def self.prompt_image(agent : Crig::Agent(M), image : Crig::Completion::Image) : String forall M
    agent.prompt(image).send
  end
end
