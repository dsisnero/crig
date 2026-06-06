require "./spec_helper"

describe "JSONUtils.deserialize_json_string_or_value" do
  it "passes through a JSON-encoded string" do
    result = Crig::JSONUtils.deserialize_json_string_or_value(%({"a":1}))
    result.should eq(%({"a":1}))
    result.should_not be_nil
  end

  it "serializes an empty object to string" do
    result = Crig::JSONUtils.deserialize_json_string_or_value(%({}))
    result.should_not be_nil
    result = result.not_nil!
    result.should eq(%({}))
  end

  it "serializes a nested object to string" do
    result = Crig::JSONUtils.deserialize_json_string_or_value(%({"path":"/tmp","depth":2}))
    result.should_not be_nil
    result = result.not_nil!
    parsed = JSON.parse(result)
    parsed["path"].as_s.should eq("/tmp")
    parsed["depth"].as_i.should eq(2)
  end

  it "serializes an array to string" do
    result = Crig::JSONUtils.deserialize_json_string_or_value(%([1,2,3]))
    result.should eq("[1,2,3]")
  end

  it "returns nil for null" do
    result = Crig::JSONUtils.deserialize_json_string_or_value("null")
    result.should be_nil
  end

  it "returns nil for missing field (empty string from parser)" do
    result = Crig::JSONUtils.deserialize_json_string_or_value("")
    result.should be_nil
  end
end
