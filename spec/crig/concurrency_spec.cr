require "../spec_helper"

describe Crig::Concurrency do
  it "captures successful fiber results" do
    result = Crig::Concurrency.run { 42 }.receive

    result.success?.should be_true
    result.unwrap.should eq(42)
  end

  it "captures raised exceptions for later unwrap" do
    result = Crig::Concurrency.run do
      raise Crig::TranscriptionError.new("boom")
    end.receive

    result.failure?.should be_true
    expect_raises(Crig::TranscriptionError, "boom") do
      result.unwrap
    end
  end
end

describe "channel-based model execution" do
  it "supports async completion sends" do
    model = FakeCompletionModel.new
    result = model.completion_request("hello").send_async(model).receive

    result.unwrap.raw_response.should eq("raw")
    request = model.last_request
    request.should_not be_nil
    request.try(&.chat_history.last.role.to_s).should eq("User")
  end

  it "supports async completion streams" do
    model = FakeCompletionModel.new
    result = model.completion_request("hello").stream_async(model).receive

    result.unwrap.should eq(["streamed"])
  end

  it "supports async audio generation sends" do
    model = FakeAudioGenerationModel.new
    result = model.audio_generation_request.text("hello").voice("alloy").send_async.receive

    result.unwrap.response.should eq("raw-audio")
  end

  it "supports async image generation sends" do
    model = FakeImageGenerationModel.new
    result = model.image_generation_request.prompt("draw a cat").send_async.receive

    result.unwrap.response.should eq("raw-image")
  end

  it "supports async transcription sends" do
    model = FakeTranscriptionModel.new
    result = model.transcription_request.data(Bytes[1_u8, 2_u8]).filename("clip.wav").send_async.receive

    result.unwrap.response.should eq("raw-transcription")
  end

  it "surfaces async transcription failures through the channel result" do
    model = FailingTranscriptionModel.new
    result = model.transcription_request.data(Bytes[1_u8, 2_u8]).filename("clip.wav").send_async.receive

    expect_raises(Crig::TranscriptionError, "provider unavailable for clip.wav") do
      result.unwrap
    end
  end
end
