require "../src/crig"

module Crig::Examples::OpenAIAudioGeneration
  DEFAULT_PATH  = "./output.mp3"
  DEFAULT_TEXT  = "The quick brown fox jumps over the lazy dog"
  DEFAULT_VOICE = "alloy"

  def self.build_model(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::TTS_1,
  ) : Crig::Providers::OpenAI::AudioGenerationModel
    client.audio_generation_model(model)
  end

  def self.build_request(
    model : Crig::AudioGenerationModel,
    text : String = DEFAULT_TEXT,
    voice : String = DEFAULT_VOICE,
  ) : Crig::AudioGenerationRequestBuilder
    model.audio_generation_request
      .text(text)
      .voice(voice)
  end

  def self.generate(
    model : Crig::AudioGenerationModel,
    text : String = DEFAULT_TEXT,
    voice : String = DEFAULT_VOICE,
  )
    build_request(model, text, voice).send
  end

  def self.write_audio(response : Crig::AudioGenerationResponse(T), io : IO) : Nil forall T
    io.write(response.audio)
  end
end
