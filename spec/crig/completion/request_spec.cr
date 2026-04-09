require "../../spec_helper"

describe Crig::Completion::Request::CompletionRequestBuilder do
  it "keeps provider tool definitions configurable" do
    definition = Crig::Completion::Request::ProviderToolDefinition.new("web_search")
      .with_config("user_location", JSON.parse(%({"city":"Denver"})))

    definition.kind.should eq("web_search")
    definition.to_json_value["user_location"]["city"].as_s.should eq("Denver")
  end

  it "tracks provider-hosted tools on the request and additional params payload" do
    hosted_tool = Crig::Completion::Request::ProviderToolDefinition.new("web_search")
      .with_config("user_location", JSON.parse(%({"city":"Denver"})))
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Who are you?")
      .provider_tool(hosted_tool)
      .provider_tools([Crig::Completion::Request::ProviderToolDefinition.new("file_search")])
      .build

    request.provider_tools.map(&.kind).should eq(["web_search", "file_search"])
    request.additional_params.not_nil!["tools"].as_a.map { |entry| entry["type"].as_s }.should eq(["web_search", "file_search"])
  end

  it "preserves preamble on the request by default" do
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Prompt")
      .preamble("System prompt")
      .message(Crig::Completion::Message.user("History"))
      .build

    request.preamble.should eq("System prompt")
    history = request.chat_history.to_a
    history.size.should eq(2)
    history.first.rag_text.should eq("History")
    history.last.rag_text.should eq("Prompt")
  end

  it "removes preamble when without_preamble is applied" do
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("Prompt")
      .preamble("System prompt")
      .without_preamble
      .build

    request.preamble.should be_nil
    request.chat_history.to_a.size.should eq(1)
    request.chat_history.to_a.first.rag_text.should eq("Prompt")
  end
end
