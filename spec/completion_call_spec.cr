require "./spec_helper"

describe "CompletionCall" do
  it "tracks call_index and optional usage" do
    usage = Crig::Completion::Usage.new(input_tokens: 10, output_tokens: 20, total_tokens: 30)
    call = Crig::CompletionCall.new(0, usage)
    call.call_index.should eq(0)
    call.usage.should_not be_nil
    call.usage.not_nil!.input_tokens.should eq(10)
  end

  it "accepts nil usage" do
    call = Crig::CompletionCall.new(1, nil)
    call.call_index.should eq(1)
    call.usage.should be_nil
  end
end

describe "PromptResponse completion_calls" do
  it "accepts and returns completion calls" do
    usage = Crig::Completion::Usage.new(input_tokens: 3, output_tokens: 4, total_tokens: 7)
    response = Crig::PromptResponse.new("ok", usage)
      .with_completion_calls([
        Crig::CompletionCall.new(0, nil),
        Crig::CompletionCall.new(1, usage),
      ])
    response.completion_calls.size.should eq(2)
    response.completion_calls[0].call_index.should eq(0)
    response.completion_calls[0].usage.should be_nil
    response.completion_calls[1].call_index.should eq(1)
    response.completion_calls[1].usage.not_nil!.input_tokens.should eq(3)
  end

  it "defaults to empty completion_calls" do
    response = Crig::PromptResponse.new("ok", Crig::Completion::Usage.new)
    response.completion_calls.should be_empty
  end
end

describe "TypedPromptResponse completion_calls" do
  it "accepts and returns completion calls" do
    usage = Crig::Completion::Usage.new(input_tokens: 4, output_tokens: 6, total_tokens: 10)
    response = Crig::TypedPromptResponse(String).new("ok", usage)
      .with_completion_calls([Crig::CompletionCall.new(0, usage)])
    response.completion_calls.size.should eq(1)
    response.completion_calls[0].call_index.should eq(0)
  end

  it "defaults to empty completion_calls" do
    response = Crig::TypedPromptResponse(String).new("ok", Crig::Completion::Usage.new)
    response.completion_calls.should be_empty
  end
end
