require "../spec_helper"

module Crig
  struct ExtractPerson
    include JSON::Serializable
    getter name : String
    getter age : Int32
  end

  describe Extractor do
    it "routes through runner when extractor uses agent runner" do
      client = Providers::DeepSeek::Client.from_env rescue nil
      unless client
        pending "DEEPSEEK_API_KEY not set"
        next
      end

      extractor = client
        .extractor(ExtractPerson, Providers::DeepSeek::DEEPSEEK_CHAT)
        .build

      result = extractor.extract("John Doe is 30 years old")
      result.should be_a(ExtractPerson)
      result.name.should eq("John Doe")
      result.age.should eq(30)
    end
  end
end
