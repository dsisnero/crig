require "./spec_helper"

describe "Text additional_params" do
  it "deserializes text without additional_params" do
    text = Crig::Completion::Text.from_json(%({"text":"hello"}))
    text.text.should eq("hello")
    text.additional_params.should be_nil
  end

  it "deserializes text with additional_params" do
    text = Crig::Completion::Text.from_json(%({"text":"hello","additional_params":{"key":"value"}}))
    text.text.should eq("hello")
    text.additional_params.should_not be_nil
    text.additional_params.not_nil!["key"].as_s.should eq("value")
  end

  it "constructs from string" do
    text = Crig::Completion::Text.from("hello")
    text.text.should eq("hello")
    text.additional_params.should be_nil
  end

  it "constructs with additional_params" do
    params = JSON.parse(%({"citations":[]}))
    text = Crig::Completion::Text.new("cited text", params)
    text.text.should eq("cited text")
    text.additional_params.should eq(params)
  end
end
