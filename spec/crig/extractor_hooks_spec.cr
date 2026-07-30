require "../spec_helper"

module Crig
  describe Extractor do
    it "routes through runner when extractor uses agent runner" do
      client = Providers::OpenAI::Client.from_env rescue nil
      unless client
        pending "OpenAI API key not set"
        next
      end

      extractor = client
        .extractor(String, Providers::OpenAI::GPT_4O_MINI)
        .build

      result = extractor.extract("Say hello world")
      result.should be_a(String)
    end
  end
end
