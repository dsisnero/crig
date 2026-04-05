require "base64"
require "../src/crig"

module Crig::Examples::ImageOllama
  IMAGE_FILE_PATH = "vendor/rig/rig/rig-core/examples/images/camponotus_flavomarginatus_ant.jpg"
  PREAMBLE        = "describe this image and make sure to include anything notable about it (include text you see in the image)"
  MODEL           = "llava"

  def self.build_agent(
    client : Crig::Providers::Ollama::Client,
    model : String = MODEL,
  )
    client.agent(model)
      .preamble(PREAMBLE)
      .temperature(0.5)
      .build
  end

  def self.image_from_bytes(image_bytes : Bytes) : Crig::Completion::Image
    Crig::Completion::Image.new(
      Crig::Completion::DocumentSourceKind.base64(Base64.strict_encode(image_bytes)),
      Crig::Completion::ImageMediaType::JPEG,
    )
  end

  def self.prompt_image(agent : Crig::Agent(M), image : Crig::Completion::Image) : String forall M
    agent.prompt(image).send
  end
end
