require "../../spec_helper"
describe Crig::Completion::CompletionError do
  it "behaves as a concrete exception wrapper" do
    error = Crig::Completion::CompletionError.provider_error("boom")
    request = Crig::Completion::CompletionError.request_error(Exception.new("bad request"))

    error.message.should eq("ProviderError: boom")
    error.kind.should eq(Crig::Completion::CompletionError::Kind::ProviderError)
    request.kind.should eq(Crig::Completion::CompletionError::Kind::RequestError)
    request.source_error.should be_a(Exception)
  end
end

describe Crig::Completion::StructuredOutputError do
  it "behaves as a concrete exception wrapper" do
    prompt = Crig::Completion::PromptError.prompt_cancelled(
      [Crig::Completion::Message.user("hello")],
      "stop",
    )
    prompt_error = Crig::Completion::StructuredOutputError.prompt_error(prompt)
    deserialization = Crig::Completion::StructuredOutputError.deserialization_error(Exception.new("bad schema"))
    empty = Crig::Completion::StructuredOutputError.empty_response

    prompt_error.message.should eq("PromptError: PromptCancelled: stop")
    prompt_error.kind.should eq(Crig::Completion::StructuredOutputError::Kind::PromptError)
    prompt_error.prompt_error.should eq(prompt)
    deserialization.kind.should eq(Crig::Completion::StructuredOutputError::Kind::DeserializationError)
    deserialization.source_error.should be_a(Exception)
    empty.message.should eq("EmptyResponse: model returned no content")
    empty.kind.should eq(Crig::Completion::StructuredOutputError::Kind::EmptyResponse)
  end
end
