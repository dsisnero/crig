require "../src/crig"

module Crig::Examples::ExtractorWithDeepSeek
  DEFAULT_TEXT = "Hello my name is John Doe! I am a software engineer."

  struct Person
    include JSON::Serializable

    getter first_name : String?
    getter last_name : String?
    getter job : String?

    def initialize(@first_name : String?, @last_name : String?, @job : String?)
    end
  end

  def self.build_extractor(
    client : Crig::Providers::DeepSeek::Client,
    model : String = Crig::Providers::DeepSeek::DEEPSEEK_CHAT,
  ) : Crig::ExtractorBuilder(Crig::Providers::DeepSeek::CompletionModel, Person)
    client.extractor(Person, model)
  end

  def self.run_extract(
    extractor : Crig::Extractor(M, Person),
    text : String = DEFAULT_TEXT,
  ) : Person forall M
    extractor.extract(text)
  end

  def self.pretty_person(person : Person) : String
    person.to_pretty_json
  end
end
