require "../../../spec_helper"

module Crig::Providers::OpenAI
  describe "OpenAI model constants" do
    it "defines GPT_5_6" do
      GPT_5_6.should eq("gpt-5.6")
    end

    it "defines GPT_5_6 variants" do
      GPT_5_6_SOL.should eq("gpt-5.6-sol")
      GPT_5_6_TERRA.should eq("gpt-5.6-terra")
      GPT_5_6_LUNA.should eq("gpt-5.6-luna")
    end
  end
end
