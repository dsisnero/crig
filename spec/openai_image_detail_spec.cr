require "./spec_helper"

describe "OpenAI base64 image detail default" do
  it "defaults missing image detail to Auto instead of raising" do
    data = Crig::Completion::DocumentSourceKind.new(
      Crig::Completion::DocumentSourceKind::Kind::Base64,
      string_value: "base64_encoded_data",
    )
    content = Crig::Completion::Image.new(
      data,
      Crig::Completion::ImageMediaType::PNG,
    )
    content.detail.should be_nil
    content.media_type.should eq(Crig::Completion::ImageMediaType::PNG)
  end
end

