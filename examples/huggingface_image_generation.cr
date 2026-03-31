require "../src/crig"

module Crig::Examples::HuggingFaceImageGeneration
  MODEL          = "stabilityai/stable-diffusion-3-medium-diffusers"
  DEFAULT_PROMPT = "A castle sitting upon a large mountain, overlooking the water."
  DEFAULT_PATH   = "./output.png"

  def self.build_model(
    client : Crig::Providers::HuggingFace::Client,
    model : String = MODEL,
  ) : Crig::Providers::HuggingFace::ImageGenerationModel
    client.image_generation_model(model)
  end

  def self.generate(
    model : Crig::ImageGenerationModel,
    prompt : String = DEFAULT_PROMPT,
  )
    model.image_generation_request
      .prompt(prompt)
      .width(1024)
      .height(1024)
      .send
  end

  def self.write_image(response : Crig::ImageGenerationResponse(String), io : IO) : Nil
    io.write(response.image)
  end
end
