require "./spec_helper"

describe "OpenRouter response image filtering" do
  it "openrouter_response_image? detects tagged images" do
    params = JSON.parse(%({"openrouter":{"response_only":true,"source":"assistant.images"}}))
    image = Crig::Completion::Image.new(
      Crig::Completion::DocumentSourceKind.new(Crig::Completion::DocumentSourceKind::Kind::Base64, string_value: "abc"),
      Crig::Completion::ImageMediaType::PNG,
      nil,
      params,
    )
    Crig::Providers::OpenRouter.openrouter_response_image?(image).should be_true
  end

  it "openrouter_response_image? returns false for untagged images" do
    image = Crig::Completion::Image.new(
      Crig::Completion::DocumentSourceKind.new(Crig::Completion::DocumentSourceKind::Kind::Base64, string_value: "abc"),
      Crig::Completion::ImageMediaType::PNG,
    )
    Crig::Providers::OpenRouter.openrouter_response_image?(image).should be_false
  end

  it "openrouter_response_image? returns false for nil additional_params" do
    image = Crig::Completion::Image.new(
      Crig::Completion::DocumentSourceKind.new(Crig::Completion::DocumentSourceKind::Kind::Url, string_value: "https://example.com/img.png"),
    )
    Crig::Providers::OpenRouter.openrouter_response_image?(image).should be_false
  end
end
