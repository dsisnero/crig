require "../spec_helper"

describe Crig::ImageGenerationRequestBuilder do
  it "builds image generation requests" do
    model = FakeImageGenerationModel.new
    request = Crig::ImageGenerationRequestBuilder.new(model)
      .prompt("draw a cat")
      .width(512)
      .height(768)
      .additional_params(JSON.parse(%({"style":"pixel"})))
      .build

    request.prompt.should eq("draw a cat")
    request.width.should eq(512)
    request.height.should eq(768)
    request.additional_params.should_not be_nil
    request.additional_params.as(JSON::Any)["style"].as_s.should eq("pixel")
  end

  it "sends image generation requests through a model" do
    model = FakeImageGenerationModel.new
    response = Crig::ImageGenerationRequestBuilder.new(model)
      .prompt("draw a cat")
      .send

    response.image.should eq(Bytes[1_u8, 2_u8, 3_u8])
    response.response.should eq("raw-image")
    model.last_request.should_not be_nil
    model.last_request.as(Crig::ImageGenerationRequest).prompt.should eq("draw a cat")
  end
end

describe Crig::AudioGenerationRequestBuilder do
  it "builds audio generation requests" do
    model = FakeAudioGenerationModel.new
    request = Crig::AudioGenerationRequestBuilder.new(model)
      .text("hello world")
      .voice("alloy")
      .speed(1.5_f32)
      .additional_params(JSON.parse(%({"format":"mp3"})))
      .build

    request.text.should eq("hello world")
    request.voice.should eq("alloy")
    request.speed.should eq(1.5_f32)
    request.additional_params.should_not be_nil
    request.additional_params.as(JSON::Any)["format"].as_s.should eq("mp3")
  end

  it "sends audio generation requests through a model" do
    model = FakeAudioGenerationModel.new
    response = Crig::AudioGenerationRequestBuilder.new(model)
      .text("hello world")
      .voice("alloy")
      .send

    response.audio.should eq(Bytes[4_u8, 5_u8])
    response.response.should eq("raw-audio")
    model.last_request.should_not be_nil
    model.last_request.as(Crig::AudioGenerationRequest).text.should eq("hello world")
    model.last_request.as(Crig::AudioGenerationRequest).voice.should eq("alloy")
  end
end

describe Crig::TranscriptionRequestBuilder do
  it "builds transcription requests" do
    model = FakeTranscriptionModel.new
    request = Crig::TranscriptionRequestBuilder.new(model)
      .data(Bytes[1_u8, 2_u8, 3_u8])
      .filename("audio.mp3")
      .language("en")
      .prompt("transcribe clearly")
      .temperature(0.5)
      .additional_params(JSON.parse(%({"format":"verbose"})))
      .build

    request.data.should eq(Bytes[1_u8, 2_u8, 3_u8])
    request.filename.should eq("audio.mp3")
    request.language.should eq("en")
    request.prompt.should eq("transcribe clearly")
    request.temperature.should eq(0.5)
    request.additional_params.should_not be_nil
    request.additional_params.as(JSON::Any)["format"].as_s.should eq("verbose")
  end

  it "loads transcription data from a file path" do
    model = FakeTranscriptionModel.new
    dir = File.join(Dir.tempdir, "crig-transcription-builder-#{Random::Secure.hex(8)}")
    Dir.mkdir_p(dir)
    path = File.join(dir, "sample.wav")

    begin
      File.write(path, "abc")

      request = Crig::TranscriptionRequestBuilder.new(model)
        .load_file(path)
        .build

      request.filename.should eq("sample.wav")
      request.data.should eq("abc".to_slice)
    ensure
      File.delete?(path)
      Dir.delete(dir)
    end
  end

  it "merges transcription additional params" do
    model = FakeTranscriptionModel.new
    request = Crig::TranscriptionRequestBuilder.new(model)
      .data(Bytes[1_u8])
      .additional_params(JSON.parse(%({"a":1})))
      .additional_params(JSON.parse(%({"b":2})))
      .build

    request.additional_params.should_not be_nil
    params = request.additional_params.as(JSON::Any)
    params["a"].as_i.should eq(1)
    params["b"].as_i.should eq(2)
  end

  it "sends transcription requests through a model" do
    model = FakeTranscriptionModel.new
    response = Crig::TranscriptionRequestBuilder.new(model)
      .data(Bytes[1_u8, 2_u8])
      .filename("audio.mp3")
      .send

    response.text.should eq("hello world")
    response.response.should eq("raw-transcription")
    model.last_request.should_not be_nil
    model.last_request.as(Crig::TranscriptionRequest).filename.should eq("audio.mp3")
  end
end
