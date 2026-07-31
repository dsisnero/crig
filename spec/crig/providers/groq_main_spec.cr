require "../../spec_helper"
describe Crig::Providers::Groq do
  it "serializes groq requests" do
    completion_request = Crig::Completion::Request::CompletionRequest.new(
      Crig::OneOrMany(Crig::Completion::Message).one(Crig::Completion::Message.user("Hello world!")),
      additional_params: JSON.parse(%({"include_reasoning":true,"reasoning_format":"parsed"}))
    )

    groq = Crig::Providers::Groq::GroqCompletionRequest.from_request("openai/gpt-120b-oss", completion_request)
    json = JSON.parse(groq.to_json)

    json.should eq(JSON.parse(%({
      "model":"openai/gpt-120b-oss",
      "messages":[{"role":"user","content":"Hello world!"}],
      "stream":false,
      "include_reasoning":true,
      "reasoning_format":"parsed"
    })))
  end

  it "supports client initialization" do
    client = Crig::Providers::Groq::Client.new("dummy-key")
    client_from_builder = Crig::Providers::Groq::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::Groq::GROQ_API_BASE_URL)
  end
end
