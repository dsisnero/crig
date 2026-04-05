require "../src/crig"

module Crig::Examples::OpenRouterMultimodal
  VISION_MODEL = "google/gemini-2.5-flash"

  IMAGE_URL       = "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/800px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
  PDF_URL         = "https://bitcoin.org/bitcoin.pdf"
  MIXED_IMAGE_URL = "https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/280px-PNG_transparency_demonstration_1.png"

  def self.build_agent(
    client : Crig::Providers::OpenRouter::Client,
    preamble : String,
    model : String = VISION_MODEL,
  ) : Crig::Agent(Crig::Providers::OpenRouter::CompletionModel)
    client.agent(model).preamble(preamble).build
  end

  def self.image_message(url : String = IMAGE_URL) : Crig::Completion::Message
    Crig::Completion::Message.user([
      Crig::Completion::UserContent.text("What do you see in this image? Describe it in detail."),
      Crig::Completion::UserContent.image_url(url, Crig::Completion::ImageMediaType::JPEG),
    ])
  end

  def self.pdf_message(url : String = PDF_URL) : Crig::Completion::Message
    Crig::Completion::Message.user([
      Crig::Completion::UserContent.text("Please summarize the key points of this document."),
      Crig::Completion::UserContent.document_url(url, Crig::Completion::DocumentMediaType::PDF),
    ])
  end

  def self.mixed_message(url : String = MIXED_IMAGE_URL) : Crig::Completion::Message
    Crig::Completion::Message.user([
      Crig::Completion::UserContent.text("I have two questions:"),
      Crig::Completion::UserContent.text("1. What colors do you see in this image?"),
      Crig::Completion::UserContent.image_url(url, Crig::Completion::ImageMediaType::PNG),
      Crig::Completion::UserContent.text("2. What is the main subject?"),
    ])
  end

  def self.run_prompt(agent : Crig::Agent(M), message : Crig::Completion::Message) : String forall M
    agent.prompt(message).send
  end
end
