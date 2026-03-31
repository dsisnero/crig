require "../src/crig"

module Crig::Examples::OpenAIImageGeneration
  DEFAULT_PATH   = "./output.png"
  DEFAULT_PROMPT = "A castle sitting upon a large mountain, overlooking the water."

  def self.build_model(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::DALL_E_2,
  ) : Crig::Providers::OpenAI::ImageGenerationModel
    client.image_generation_model(model)
  end

  def self.build_request(
    model : Crig::ImageGenerationModel,
    prompt : String = DEFAULT_PROMPT,
    width : Int32 = 1024,
    height : Int32 = 1024,
  ) : Crig::ImageGenerationRequestBuilder
    model.image_generation_request
      .prompt(prompt)
      .width(width)
      .height(height)
  end

  def self.generate(
    model : Crig::ImageGenerationModel,
    prompt : String = DEFAULT_PROMPT,
    width : Int32 = 1024,
    height : Int32 = 1024,
  )
    build_request(model, prompt, width, height).send
  end

  def self.write_image(response : Crig::ImageGenerationResponse(T), io : IO) : Nil forall T
    io.write(response.image)
  end
end
