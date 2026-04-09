require "../../../spec_helper"

describe Crig::Providers::XAI::Client do
  it "supports xai client initialization from the builder" do
    client = Crig::Providers::XAI::Client.builder
      .api_key("dummy-key")
      .build

    client.base_url.should eq(Crig::Providers::XAI::XAI_BASE_URL)
  end

  it "supports xai helper constructors and agent builders" do
    auth_client = Crig::Providers::XAI::Client.from_val(Crig::BearerAuth.new("dummy-key"))
    auth_client.api_key.token.should eq("dummy-key")

    agent = auth_client.agent(Crig::Providers::XAI::GROK_3_MINI)
      .name("assistant")
      .build
    agent.model.model.should eq(Crig::Providers::XAI::GROK_3_MINI)

    request = auth_client.completion_model(Crig::Providers::XAI::GROK_3)
      .completion_request("hello")
      .build
    request.model.should eq(Crig::Providers::XAI::GROK_3)
  end

  it "supports xai completion-model with_model helpers" do
    client = Crig::Providers::XAI::Client.new("dummy-key")

    class_level = Crig::Providers::XAI::CompletionModel.with_model(client, Crig::Providers::XAI::GROK_3)
    class_level.client.should eq(client)
    class_level.model.should eq(Crig::Providers::XAI::GROK_3)

    instance_level = class_level.with_model(Crig::Providers::XAI::GROK_3_MINI)
    instance_level.client.should eq(client)
    instance_level.model.should eq(Crig::Providers::XAI::GROK_3_MINI)
  end

  it "exposes xai audio and image generation model helpers" do
    client = Crig::Providers::XAI::Client.new("dummy-key")

    client.audio_generation_model(Crig::Providers::XAI::TTS_1).model.should eq(Crig::Providers::XAI::TTS_1)
    client.image_generation_model(Crig::Providers::XAI::GROK_IMAGINE_IMAGE).model.should eq(Crig::Providers::XAI::GROK_IMAGINE_IMAGE)
  end

  it "posts xai responses requests and parses the returned response" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"resp_xai",
          "model":"grok-3",
          "output":[
            {
              "type":"message",
              "id":"msg_xai",
              "role":"assistant",
              "status":"completed",
              "content":[{"type":"output_text","text":"xai answer"}]
            }
          ],
          "usage":{"input_tokens":2,"output_tokens":1,"total_tokens":3}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::XAI::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::XAI::GROK_3)
      .completion(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    response.choice.first.text.not_nil!.text.should eq("xai answer")
    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::XAI::GROK_3)
    posted["input"].as_a.first["type"].as_s.should eq("message")

    http_server.close
  end

  it "posts xai audio generation requests and returns binary audio bytes" do
    server = FakeXAIAudioGenerationServer.new do |_request|
      {
        content_type: "application/octet-stream",
        body:         "audio-bytes",
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::XAI::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.audio_generation_model(Crig::Providers::XAI::TTS_1)
      .audio_generation(Crig::AudioGenerationRequest.new("hello", "", 1.0_f32, JSON.parse(%({"speaker":"narrator"}))))

    String.new(response.audio).should eq("audio-bytes")
    String.new(response.response).should eq("audio-bytes")

    posted = server.requests.first
    posted["text"].as_s.should eq("hello")
    posted["voice_id"].as_s.should eq("eve")
    posted["language"].as_s.should eq("en")
    posted["speaker"].as_s.should eq("narrator")

    http_server.close
  end

  it "posts xai image generation requests and decodes base64 image bytes" do
    encoded = Base64.strict_encode("png-bytes")
    server = FakeXAIImageGenerationServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({"data":[{"b64_json":"#{encoded}"}]}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::XAI::Client.new("test-key", "http://127.0.0.1:#{address.port}")
    response = client.image_generation_model(Crig::Providers::XAI::GROK_IMAGINE_IMAGE)
      .image_generation(Crig::ImageGenerationRequest.new("A cat", 1024, 1024, JSON.parse(%({"style":"comic"}))))

    String.new(response.image).should eq("png-bytes")
    response.response.data.size.should eq(1)

    posted = server.requests.first
    posted["model"].as_s.should eq(Crig::Providers::XAI::GROK_IMAGINE_IMAGE)
    posted["prompt"].as_s.should eq("A cat")
    posted["response_format"].as_s.should eq("b64_json")
    posted["style"].as_s.should eq("comic")

    http_server.close
  end
end
