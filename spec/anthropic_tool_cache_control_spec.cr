require "./spec_helper"

describe "Anthropic ToolDefinition cache_control" do
  it "serializes cache_control on tool definition" do
    tool = Crig::Providers::Anthropic::ToolDefinition.new(
      "search",
      JSON.parse(%({"type":"object","properties":{}})),
      "Search the web",
      cache_control: Crig::Providers::Anthropic::CacheControl.ephemeral,
    )
    json = JSON.parse(tool.to_json_value.to_json)
    json["name"].as_s.should eq("search")
    json["cache_control"]["type"].as_s.should eq("ephemeral")
  end

  it "omits cache_control from JSON when nil" do
    tool = Crig::Providers::Anthropic::ToolDefinition.new(
      "search",
      JSON.parse(%({"type":"object","properties":{}})),
      "Search the web",
    )
    json = JSON.parse(tool.to_json_value.to_json)
    json["name"].as_s.should eq("search")
    json.as_h.has_key?("cache_control").should be_false
  end
end
