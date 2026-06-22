require "./spec_helper"

class FakePromptStreamingModel
  include Crig::Completion::CompletionModel

  def completion(request : Crig::Completion::Request::CompletionRequest)
    Crig::Completion::CompletionResponse(String).new(
      Crig::OneOrMany(Crig::Completion::AssistantContent).one(Crig::Completion::AssistantContent.text("ok")),
      Crig::Completion::Usage.new,
      "raw",
    )
  end

  def stream(request : Crig::Completion::Request::CompletionRequest)
    Crig::StreamingCompletionResponse(Crig::MockResponse).stream(
      ["streamed"],
      Crig::MockResponse.new(1),
    )
  end

  def completion_request(prompt : Crig::Completion::Message | String) : Crig::Completion::Request::CompletionRequestBuilder
    Crig::Completion::Request::CompletionRequestBuilder.from_prompt(prompt)
  end
end

describe "prompt request async APIs" do
  it "supports async agent prompt sends" do
    model = FakeCompletionModel.new
    agent = Crig::Agent(FakeCompletionModel).new(model)

    result = agent.prompt("hello").send_async.receive

    result.unwrap.should eq("ok")
    request = model.last_request
    request.should_not be_nil
    request.try(&.chat_history.last.role.to_s).should eq("User")
  end

  it "supports async streaming prompt sends" do
    agent = Crig::Agent(FakePromptStreamingModel).new(FakePromptStreamingModel.new)

    result = agent.stream_prompt("hello").send_async.receive

    stream = result.unwrap
    stream.response.not_nil!.response.should eq("streamed")
    stream.chunks.should eq(["streamed"])
  end
end
