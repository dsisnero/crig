require "../src/crig"

module Crig::Examples::Extractor
  struct Person
    include JSON::Serializable

    getter first_name : String?
    getter last_name : String?
    getter job : String?

    def initialize(
      @first_name : String? = nil,
      @last_name : String? = nil,
      @job : String? = nil,
    )
    end
  end

  def self.build_extractor(
    client : Crig::Providers::OpenAI::Client,
    model : String = Crig::Providers::OpenAI::GPT_4,
  ) : Crig::ExtractorBuilder(Crig::Providers::OpenAI::ResponsesCompletionModel, Person)
    client.extractor(Person, model)
  end

  def self.pretty_person(person : Person) : String
    JSON.parse(person.to_json).to_pretty_json
  end

  def self.pretty_response(response : Crig::ExtractionResponse(Person)) : String
    JSON.parse(response.data.to_json).to_pretty_json
  end
end
