require "../src/crig"

module Crig::Examples::GeminiExtractor
  struct FooString
    include JSON::Serializable

    getter string : String

    def initialize(@string : String)
    end
  end

  struct Person
    include JSON::Serializable

    getter first_name : String?
    getter last_name : String?
    getter job : FooString?

    def initialize(@first_name : String? = nil, @last_name : String? = nil, @job : FooString? = nil)
    end
  end

  def self.additional_params(
    generation_config : Crig::Providers::Gemini::GenerationConfig = Crig::Providers::Gemini::GenerationConfig.new,
  ) : JSON::Any
    JSON.parse(%({"generationConfig":#{generation_config.to_json}}))
  end

  def self.build_extractor(
    client : Crig::Providers::Gemini::Client,
    model : String = Crig::Providers::Gemini::GEMINI_2_0_FLASH,
    generation_config : Crig::Providers::Gemini::GenerationConfig = Crig::Providers::Gemini::GenerationConfig.new,
  ) : Crig::ExtractorBuilder(Crig::Providers::Gemini::CompletionModel, Person)
    client.extractor(Person, model).additional_params(additional_params(generation_config))
  end
end
