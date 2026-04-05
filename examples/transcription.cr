require "../src/crig"

module Crig::Examples::Transcription
  def self.whisper_model(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::WHISPER_1,
  ) : Crig::Providers::OpenAI::TranscriptionModel
    client.transcription_model(model)
  end

  def self.gemini_model(
    client : Crig::Providers::Gemini::Client,
    model : String = Crig::Providers::Gemini::GEMINI_2_0_FLASH,
  ) : Crig::Providers::Gemini::TranscriptionModel
    client.transcription_model(model)
  end

  def self.azure_model(
    client : Crig::Providers::Azure::Client,
    model : String = "whisper",
  ) : Crig::Providers::Azure::TranscriptionModel
    client.transcription_model(model)
  end

  def self.groq_model(
    client : Crig::Providers::Groq::Client,
    model : String = Crig::Providers::Groq::WHISPER_LARGE_V3,
  ) : Crig::Providers::Groq::TranscriptionModel
    client.transcription_model(model)
  end

  def self.huggingface_model(
    client : Crig::Providers::HuggingFace::Client,
    model : String = "whisper-large-v3",
  ) : Crig::Providers::HuggingFace::TranscriptionModel
    client.transcription_model(model)
  end

  def self.mistral_model(
    client : Crig::Providers::Mistral::Client,
    model : String = Crig::Providers::Mistral::VOXTRAL_MINI,
  ) : Crig::Providers::Mistral::TranscriptionModel
    client.transcription_model(model)
  end

  def self.transcribe(model : Crig::TranscriptionModel, file_path : String) : String
    model.transcription_request
      .load_file(file_path)
      .send
      .text
  end
end
