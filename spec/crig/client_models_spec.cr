require "../spec_helper"
describe Crig::ProviderBuilder(FakeProviderExtension, Crig::BearerAuth) do
  it "exposes base_url, build, and default finish hooks" do
    builder = FakeProviderBuilder.new
    client_builder = Crig::Client::ClientBuilder(FakeProviderBuilder, Crig::BearerAuth, String).new(
      builder,
      Crig::BearerAuth.new("secret"),
      "https://api.example.com",
      {"X-Test" => "1"},
      "http",
    )

    builder.base_url.should eq("https://api.example.com")
    builder.finish(client_builder).should eq(client_builder)
    builder.build(client_builder).should be_a(FakeProviderExtension)
  end
end

describe Crig::Client::Client(FakeProviderExtension, String) do
  it "builds lightweight clients directly and exposes base_url/ext state" do
    client = Crig::Client::Client(FakeProviderExtension, String).new(
      FakeProviderExtension.new,
      base_url: "https://api.example.com",
      headers: {"X-Test" => "1"},
      http_client: "http",
    )

    client.base_url.should eq("https://api.example.com")
    client.headers.should eq({"X-Test" => "1"})
    client.http_client.should eq("http")
    client.ext.should be_a(FakeProviderExtension)
  end

  it "supports deriving a client with a different extension" do
    client = Crig::Client::Client(FakeProviderExtension, String).new(
      FakeProviderExtension.new,
      base_url: "https://api.example.com",
      http_client: "http",
    )
    updated = client.with_ext(:updated)

    updated.base_url.should eq("https://api.example.com")
    updated.http_client.should eq("http")
    updated.ext.should eq(:updated)
  end

  it "builds request metadata for post/get and sse helpers" do
    client = Crig::Client::Client(FakeProviderExtension, String).new(
      FakeProviderExtension.new,
      base_url: "https://api.example.com",
      headers: {"Authorization" => "Bearer secret"},
      http_client: "http",
    )

    client.post("/chat").body("{}").method.should eq("POST")
    client.post("/chat").uri.should eq("https://api.example.com/chat")
    client.post("/chat").headers.should eq({"Authorization" => "Bearer secret"})
    client.post("/chat").body_value.should eq("customized")
    client.get("/models").method.should eq("GET")
    client.get_sse("/events").uri.should eq("https://api.example.com/events")
    client.post_sse("/stream").uri.should eq("https://api.example.com/stream")
  end
end

describe Crig::Client::ClientBuilder(FakeProviderExtension, Crig::NeedsApiKey, Nil), tags: %w[client_builder] do
  it "supports base_url, headers, and api_key composition before build" do
    builder = Crig::Client::Client.builder(FakeProviderExtension.new)
      .base_url("https://api.example.com")
      .http_headers({"X-Test" => "1"})
      .api_key(Crig::BearerAuth.new("secret"))

    client = builder.build

    client.base_url.should eq("https://api.example.com")
    client.headers.should eq({
      "X-Test"        => "1",
      "Authorization" => "Bearer secret",
    })
  end

  it "supports swapping the http client and exposing the ext builder" do
    builder = Crig::Client::Client.builder(FakeProviderExtension.new)
      .http_client("http-backend")

    builder.ext.should be_a(FakeProviderExtension)
    builder.build.http_client.should eq("http-backend")
  end
end

describe Crig::ModelListingClient, tags: %w[model_listing client] do
  it "lists all models through the client interface" do
    client = FakeModelListingClient.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
      Crig::ModelInfo.new("gpt-3.5-turbo", "GPT-3.5 Turbo"),
    ])

    models = client.list_models

    models.len.should eq(2)
    models.data[0].display_name.should eq("GPT-4")
  end

  it "lists all models asynchronously through the client interface" do
    client = FakeModelListingClient.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
    ])

    models = client.list_models_async.receive.unwrap

    models.len.should eq(1)
    models.data[0].display_name.should eq("GPT-4")
  end
end

describe Crig::ModelLister(Array(Crig::ModelInfo)), tags: %w[model_listing lister] do
  it "lists all models through the lister interface" do
    lister = FakeModelLister.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
      Crig::ModelInfo.new("gpt-3.5-turbo", "GPT-3.5 Turbo"),
    ])

    models = lister.list_all

    models.len.should eq(2)
    models.data[1].display_name.should eq("GPT-3.5 Turbo")
  end

  it "lists all models asynchronously through the lister interface" do
    lister = FakeModelLister.new([
      Crig::ModelInfo.new("gpt-4", "GPT-4"),
    ])

    models = lister.list_all_async.receive.unwrap

    models.len.should eq(1)
    models.data[0].display_name.should eq("GPT-4")
  end
end

describe Crig::AudioGenerationClient(FakeAudioGenerationClientModel), tags: %w[audio_generation client] do
  it "builds audio generation models through the client interface" do
    client = FakeAudioGenerationClient.new
    model = client.audio_generation_model("tts-1")
    response = model.audio_generation_request.text("hello").voice("alloy").send

    model.name.should eq("tts-1")
    response.response.should eq("audio:tts-1")
    model.last_request.try(&.voice).should eq("alloy")
  end
end

describe Crig::AudioGenerationClientDyn, tags: %w[audio_generation client_dyn] do
  it "builds dynamic audio generation models" do
    client = FakeAudioGenerationClient.new.as(Crig::AudioGenerationClientDyn)
    model = client.audio_generation_model("tts-1")
    response = model.audio_generation_request.text("hello").voice("alloy").send

    response.response.should eq("audio:tts-1")
  end
end

describe Crig::AudioGenerationModelHandle, tags: %w[audio_generation model_handle] do
  it "wraps a dynamic model for the request builder" do
    inner = FakeAudioGenerationClientModel.new("tts-1").as(Crig::AudioGenerationModelDyn)
    handle = Crig::AudioGenerationModelHandle.new(inner)
    response = handle.audio_generation_request.text("hello").voice("alloy").send

    response.response.should eq("audio:tts-1")
  end

  it "raises on the unsupported make path" do
    expect_raises(Exception, "Invalid method: Cannot make an AudioGenerationModelHandle from a client + model identifier") do
      Crig::AudioGenerationModelHandle.make(nil, "tts-1")
    end
  end
end

describe Crig::ImageGenerationClient(FakeImageGenerationClientModel), tags: %w[image_generation client] do
  it "builds image generation models through the client interface" do
    client = FakeImageGenerationClient.new
    model = client.image_generation_model("dall-e-3")
    response = model.image_generation_request.prompt("draw a cat").width(512).height(768).send

    model.name.should eq("dall-e-3")
    response.response.should eq("image:dall-e-3")
    model.last_request.try(&.width).should eq(512)
  end

  it "supports the custom image-generation helper" do
    client = FakeImageGenerationClient.new

    client.custom_image_generation_model("custom-model").name.should eq("custom-model")
  end
end

describe Crig::ImageGenerationClientDyn, tags: %w[image_generation client_dyn] do
  it "builds dynamic image generation models" do
    client = FakeImageGenerationClient.new.as(Crig::ImageGenerationClientDyn)
    model = client.image_generation_model("dall-e-3")
    response = model.image_generation_request.prompt("draw a cat").send

    response.response.should eq("image:dall-e-3")
  end
end

describe Crig::ImageGenerationModelHandle, tags: %w[image_generation model_handle] do
  it "wraps a dynamic image model for the request builder" do
    inner = FakeImageGenerationClientModel.new("dall-e-3").as(Crig::ImageGenerationModelDyn)
    handle = Crig::ImageGenerationModelHandle.new(inner)
    response = handle.image_generation_request.prompt("draw a cat").send

    response.response.should eq("image:dall-e-3")
  end

  it "raises on the unsupported make path" do
    expect_raises(Exception, "Invalid method: Cannot make an ImageGenerationModelHandle from a client + model identifier") do
      Crig::ImageGenerationModelHandle.make(nil, "dall-e-3")
    end
  end
end

describe Crig::TranscriptionClient(FakeTranscriptionClientModel), tags: %w[transcription client] do
  it "builds transcription models through the client interface" do
    client = FakeTranscriptionClient.new
    model = client.transcription_model("whisper-1")
    response = model.transcription_request.data(Bytes[1_u8, 2_u8]).filename("clip.wav").send

    model.name.should eq("whisper-1")
    response.response.should eq("transcription:whisper-1")
    model.last_request.try(&.filename).should eq("clip.wav")
  end
end

describe Crig::TranscriptionClientDyn, tags: %w[transcription client_dyn] do
  it "builds dynamic transcription models" do
    client = FakeTranscriptionClient.new.as(Crig::TranscriptionClientDyn)
    model = client.transcription_model("whisper-1")
    response = model.transcription_request.data(Bytes[1_u8, 2_u8]).send

    response.response.should eq("transcription:whisper-1")
  end
end

describe Crig::TranscriptionModelHandle, tags: %w[transcription model_handle] do
  it "wraps a dynamic transcription model for the request builder" do
    inner = FakeTranscriptionClientModel.new("whisper-1").as(Crig::TranscriptionModelDyn)
    handle = Crig::TranscriptionModelHandle.new(inner)
    response = handle.transcription_request.data(Bytes[1_u8, 2_u8]).send

    response.response.should eq("transcription:whisper-1")
  end

  it "raises on the unsupported make path" do
    expect_raises(Exception, "Invalid method: Cannot make a TranscriptionModelHandle from a client + model identifier") do
      Crig::TranscriptionModelHandle.make(nil, "whisper-1")
    end
  end
end

describe "media generation error helpers" do
  it "exposes audio-generation error variants with source retention" do
    error = Crig::AudioGenerationError.provider_error("audio failed")
    request = Crig::AudioGenerationError.request_error(Exception.new("bad form"))

    error.message.should eq("ProviderError: audio failed")
    error.kind.should eq(Crig::AudioGenerationError::Kind::ProviderError)
    request.kind.should eq(Crig::AudioGenerationError::Kind::RequestError)
    request.source_error.should be_a(Exception)
  end

  it "exposes image-generation error variants with source retention" do
    error = Crig::ImageGenerationError.response_error("bad image")
    json = Crig::ImageGenerationError.json_error(Exception.new("bad json"))

    error.message.should eq("ResponseError: bad image")
    error.kind.should eq(Crig::ImageGenerationError::Kind::ResponseError)
    json.kind.should eq(Crig::ImageGenerationError::Kind::JsonError)
    json.source_error.should be_a(Exception)
  end

  it "exposes transcription error variants with source retention" do
    error = Crig::TranscriptionError.http_error(Exception.new("timeout"))
    provider = Crig::TranscriptionError.provider_error("unavailable")

    error.message.should eq("HttpError: timeout")
    error.kind.should eq(Crig::TranscriptionError::Kind::HttpError)
    error.source_error.should be_a(Exception)
    provider.kind.should eq(Crig::TranscriptionError::Kind::ProviderError)
  end
end
