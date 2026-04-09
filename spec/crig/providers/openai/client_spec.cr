require "../../../spec_helper"

describe Crig::Providers::OpenAI::Client do
  it "builds websocket sessions from the responses client" do
    client = Crig::Providers::OpenAI::Client.new("test-key", "https://api.openai.com/v1")
    builder = client.responses_websocket_builder(Crig::Providers::OpenAI::GPT_4O)

    builder.model.model.should eq(Crig::Providers::OpenAI::GPT_4O)
    builder.connect_timeout.should eq(30.seconds)
  end
end
