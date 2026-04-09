require "../../../spec_helper"

describe Crig::Providers::OpenAI::ResponsesToolDefinition do
  it "builds hosted tool helpers and preserves hosted config" do
    web_search = Crig::Providers::OpenAI::ResponsesToolDefinition.web_search
      .with_config("user_location", JSON.parse(%({"type":"approximate","city":"Denver"})))

    web_search.kind.should eq("web_search")
    web_search.strict?.should be_false
    web_search.to_json_value["user_location"]["city"].as_s.should eq("Denver")

    file_search = Crig::Providers::OpenAI::ResponsesToolDefinition.file_search
    computer_use = Crig::Providers::OpenAI::ResponsesToolDefinition.computer_use

    file_search.kind.should eq("file_search")
    computer_use.kind.should eq("computer_use")
  end
end
