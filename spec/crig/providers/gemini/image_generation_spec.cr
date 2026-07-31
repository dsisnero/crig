require "../../../spec_helper"

module Crig::Providers::Gemini
  describe ImageGenerationModel do
    it "initializes with default model" do
      client = Client.new("sk-test")
      model = ImageGenerationModel.new(client)
      model.model.should eq("gemini-2.5-flash-image")
    end

    it "initializes with custom model" do
      client = Client.new("sk-test")
      model = ImageGenerationModel.new(client, "custom-model")
      model.model.should eq("custom-model")
    end

    it "computes aspect ratio 1:1 for equal dimensions" do
      model = ImageGenerationModel.new(Client.new("sk-test"))
      ratio = model.compute_aspect_ratio(256, 256)
      ratio.should eq("1:1")
    end

    it "computes aspect ratio 16:9" do
      model = ImageGenerationModel.new(Client.new("sk-test"))
      ratio = model.compute_aspect_ratio(1600, 900)
      ratio.should eq("16:9")
    end

    it "computes aspect ratio 9:16" do
      model = ImageGenerationModel.new(Client.new("sk-test"))
      ratio = model.compute_aspect_ratio(900, 1600)
      ratio.should eq("9:16")
    end

    it "returns nil for non-standard dimensions" do
      model = ImageGenerationModel.new(Client.new("sk-test"))
      ratio = model.compute_aspect_ratio(100, 200)
      ratio.should be_nil
    end

    it "posts the upstream image generation request shape" do
      server = FakeGeminiGenerateContentServer.new do |_request|
        {
          content_type: "application/json",
          body:         %({"candidates":[{"content":{"role":"model","parts":[{"inlineData":{"mimeType":"image/png","data":"aGVsbG8="}}]}}],"modelVersion":"gemini-2.5-flash-image","responseId":"r1"}),
          status_code:  200,
        }
      end
      http_server = server.http_server
      address = http_server.bind_tcp("127.0.0.1", 0)
      spawn { http_server.listen }

      client = Client.new("sk-test", "http://127.0.0.1:#{address.port}")
      model = ImageGenerationModel.new(client)

      response = model.image_generation(
        Crig::ImageGenerationRequest.new("Generate an image of an axolotl", 1024, 1024)
      )
      response.image.should eq("hello".to_slice)

      posted = server.requests.first
      posted["contents"][0]["role"].as_s.should eq("user")
      posted["contents"][0]["parts"][0]["text"].as_s.should eq("Generate an image of an axolotl")
      posted["generationConfig"]["responseModalities"][0].as_s.should eq("IMAGE")
      posted["generationConfig"]["imageConfig"]["aspectRatio"].as_s.should eq("1:1")
      server.requests.size.should eq(1)

      http_server.close
    end

    it "deep-merges additional params into the request body" do
      server = FakeGeminiGenerateContentServer.new do |_request|
        {
          content_type: "application/json",
          body:         %({"candidates":[{"content":{"role":"model","parts":[{"inlineData":{"mimeType":"image/png","data":"aGVsbG8="}}]}}],"modelVersion":"gemini-2.5-flash-image","responseId":"r1"}),
          status_code:  200,
        }
      end
      http_server = server.http_server
      address = http_server.bind_tcp("127.0.0.1", 0)
      spawn { http_server.listen }

      client = Client.new("sk-test", "http://127.0.0.1:#{address.port}")
      model = ImageGenerationModel.new(client)

      model.image_generation(
        Crig::ImageGenerationRequest.new(
          "Generate an image of an axolotl",
          1024,
          1024,
          JSON.parse(%({"generationConfig":{"imageConfig":{"aspectRatio":"16:9","imageSize":"2K"}}}))
        )
      )

      posted = server.requests.first
      posted["generationConfig"]["imageConfig"]["aspectRatio"].as_s.should eq("16:9")
      posted["generationConfig"]["imageConfig"]["imageSize"].as_s.should eq("2K")
      posted["generationConfig"]["responseModalities"][0].as_s.should eq("IMAGE")

      http_server.close
    end

    it "preserves status and body for non-success responses" do
      server = FakeGeminiGenerateContentServer.new do |_request|
        {
          content_type: "application/json",
          body:         %({"error":{"code":503,"message":"boom","status":"UNAVAILABLE"}}),
          status_code:  503,
        }
      end
      http_server = server.http_server
      address = http_server.bind_tcp("127.0.0.1", 0)
      spawn { http_server.listen }

      client = Client.new("sk-test", "http://127.0.0.1:#{address.port}")
      model = ImageGenerationModel.new(client)

      error = expect_raises(Crig::ImageGenerationError) do
        model.image_generation(Crig::ImageGenerationRequest.new("draw a cat", 1024, 1024))
      end

      error.kind.should eq(Crig::ImageGenerationError::Kind::HttpError)
      error.provider_response_status.should eq(503)
      error.provider_response_body.should eq(%({"error":{"code":503,"message":"boom","status":"UNAVAILABLE"}}))

      http_server.close
    end

    it "preserves status and body for a 2xx error envelope" do
      server = FakeGeminiGenerateContentServer.new do |_request|
        {
          content_type: "application/json",
          body:         %({"error":{"code":503,"message":"boom","status":"UNAVAILABLE"}}),
          status_code:  200,
        }
      end
      http_server = server.http_server
      address = http_server.bind_tcp("127.0.0.1", 0)
      spawn { http_server.listen }

      client = Client.new("sk-test", "http://127.0.0.1:#{address.port}")
      model = ImageGenerationModel.new(client)

      error = expect_raises(Crig::ImageGenerationError) do
        model.image_generation(Crig::ImageGenerationRequest.new("draw a cat", 1024, 1024))
      end

      error.kind.should eq(Crig::ImageGenerationError::Kind::ProviderResponse)
      error.provider_response_status.should eq(200)
      error.provider_response_body.should eq(%({"error":{"code":503,"message":"boom","status":"UNAVAILABLE"}}))

      http_server.close
    end

    it "raises when the response contains no image data" do
      server = FakeGeminiGenerateContentServer.new do |_request|
        {
          content_type: "application/json",
          body:         %({"candidates":[{"content":{"role":"model","parts":[{"text":"No image"}]}}],"modelVersion":"gemini-2.5-flash-image","responseId":"r1"}),
          status_code:  200,
        }
      end
      http_server = server.http_server
      address = http_server.bind_tcp("127.0.0.1", 0)
      spawn { http_server.listen }

      client = Client.new("sk-test", "http://127.0.0.1:#{address.port}")
      model = ImageGenerationModel.new(client)

      error = expect_raises(Crig::ImageGenerationError, /did not include image data/) do
        model.image_generation(Crig::ImageGenerationRequest.new("draw a cat", 1024, 1024))
      end

      error.kind.should eq(Crig::ImageGenerationError::Kind::ResponseError)

      http_server.close
    end
  end
end
