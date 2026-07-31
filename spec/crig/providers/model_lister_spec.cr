require "../../spec_helper"
describe Crig::Providers::OpenAI::OpenAIModelLister do
  it "instantiates with an OpenAI client" do
    client = Crig::Providers::OpenAI::Client.new("test-key")
    lister = Crig::Providers::OpenAI::OpenAIModelLister.new(client)
    lister.should be_a(Crig::Providers::OpenAI::OpenAIModelLister)
  end
end

describe Crig::Providers::Anthropic::AnthropicModelLister do
  it "instantiates with an Anthropic client" do
    client = Crig::Providers::Anthropic::Client.new("test-key")
    lister = Crig::Providers::Anthropic::AnthropicModelLister.new(client)
    lister.should be_a(Crig::Providers::Anthropic::AnthropicModelLister)
  end
end

describe Crig::Providers::DeepSeek::DeepSeekModelLister do
  it "instantiates with a DeepSeek client" do
    client = Crig::Providers::DeepSeek::Client.new("test-key")
    lister = Crig::Providers::DeepSeek::DeepSeekModelLister.new(client)
    lister.should be_a(Crig::Providers::DeepSeek::DeepSeekModelLister)
  end
end

describe Crig::Providers::Gemini::GeminiModelLister do
  it "instantiates with a Gemini client" do
    client = Crig::Providers::Gemini::Client.new("test-key")
    lister = Crig::Providers::Gemini::GeminiModelLister.new(client)
    lister.should be_a(Crig::Providers::Gemini::GeminiModelLister)
  end
end

describe Crig::Providers::Mistral::MistralModelLister do
  it "instantiates with a Mistral client" do
    client = Crig::Providers::Mistral::Client.new("test-key")
    lister = Crig::Providers::Mistral::MistralModelLister.new(client)
    lister.should be_a(Crig::Providers::Mistral::MistralModelLister)
  end
end

describe Crig::Providers::OpenRouter::OpenRouterModelLister do
  it "instantiates with an OpenRouter client" do
    client = Crig::Providers::OpenRouter::Client.new("test-key")
    lister = Crig::Providers::OpenRouter::OpenRouterModelLister.new(client)
    lister.should be_a(Crig::Providers::OpenRouter::OpenRouterModelLister)
  end
end

describe Crig::Providers::Ollama::OllamaModelLister do
  it "instantiates with an Ollama client" do
    client = Crig::Providers::Ollama::Client.new
    lister = Crig::Providers::Ollama::OllamaModelLister.new(client)
    lister.should be_a(Crig::Providers::Ollama::OllamaModelLister)
  end
end

describe Crig::Providers::OpenRouter::AudioGenerationModel do
  it "instantiates with model constants" do
    Crig::Providers::OpenRouter::GPT_4O_MINI_TTS.should eq("openai/gpt-4o-mini-tts-2025-12-15")
    Crig::Providers::OpenRouter::KOKORO_82M.should eq("hexgrad/kokoro-82m")
  end
end

describe Crig::Providers::OpenRouter::TranscriptionModel do
  it "instantiates with model constants" do
    Crig::Providers::OpenRouter::WHISPER_1.should eq("openai/whisper-1")
    Crig::Providers::OpenRouter::CHIRP_3.should eq("google/chirp-3")
  end

  it "creates a transcription model through the client" do
    client = Crig::Providers::OpenRouter::Client.new("test-key")
    model = client.transcription_model(Crig::Providers::OpenRouter::WHISPER_1)
    model.should be_a(Crig::Providers::OpenRouter::TranscriptionModel)
    model.model.should eq(Crig::Providers::OpenRouter::WHISPER_1)
  end
end
