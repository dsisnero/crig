require "../../../spec_helper"

describe Crig::Providers::Gemini do
  it "exposes the new preview model constants" do
    Crig::Providers::Gemini::GEMINI_3_FLASH_PREVIEW.should eq("gemini-3-flash-preview")
    Crig::Providers::Gemini::GEMINI_3_1_FLASH_LITE_PREVIEW.should eq("gemini-3.1-flash-lite-preview")
  end

  it "defines thinking levels for preview reasoning controls" do
    Crig::Providers::Gemini::ThinkingLevel.parse("Low").should eq(Crig::Providers::Gemini::ThinkingLevel::Low)
    Crig::Providers::Gemini::ThinkingLevel.parse("Medium").should eq(Crig::Providers::Gemini::ThinkingLevel::Medium)
    Crig::Providers::Gemini::ThinkingLevel.parse("High").should eq(Crig::Providers::Gemini::ThinkingLevel::High)
  end
end
