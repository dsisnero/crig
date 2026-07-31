require "../../spec_helper"
describe Crig::Providers::Azure::Client do
  it "supports azure client builders and token default auth" do
    client = Crig::Providers::Azure::Client.builder
      .api_key("token-value")
      .azure_endpoint("https://example.openai.azure.com")
      .api_version("2024-10-01-preview")
      .build

    client.endpoint.should eq("https://example.openai.azure.com")
    client.api_version.should eq("2024-10-01-preview")
    client.auth.kind.should eq(Crig::Providers::Azure::AzureOpenAIAuth::Kind::Token)
  end

  it "posts azure embedding requests against deployment endpoints" do
    path = "/openai/deployments/#{Crig::Providers::Azure::TEXT_EMBEDDING_3_SMALL}/embeddings?api-version=2024-10-21"
    server = FakeAzureJsonServer.new(path) do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[0.1,0.2],"index":0}],
          "model":"text-embedding-3-small",
          "usage":{"prompt_tokens":1,"completion_tokens":0,"total_tokens":1}
        }),
        status_code: nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.api_key("azure-key"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    model = client.embedding_model(Crig::Providers::Azure::TEXT_EMBEDDING_3_SMALL)
    embeddings = model.embed_texts(["alpha"])

    embeddings.first.document.should eq("alpha")
    embeddings.first.vec.should eq([0.1, 0.2])
    server.requests.first["dimensions"].as_i.should eq(1536)
    server.headers.first["api-key"].should eq("azure-key")

    http_server.close
  end

  it "posts azure chat completion requests and parses the returned response" do
    path = "/openai/deployments/#{Crig::Providers::Azure::GPT_4O}/chat/completions?api-version=2024-10-21"
    server = FakeAzureJsonServer.new(path) do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"chatcmpl-azure",
          "object":"chat.completion",
          "created":1,
          "model":"gpt-4o",
          "choices":[
            {
              "index":0,
              "message":{"role":"assistant","content":"azure answer"},
              "finish_reason":"stop"
            }
          ],
          "usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}
        }),
        status_code: nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.api_key("azure-key"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    response = client.completion_model(Crig::Providers::Azure::GPT_4O)
      .completion(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    response.choice.first.text.not_nil!.text.should eq("azure answer")
    server.requests.first["model"].as_s.should eq(Crig::Providers::Azure::GPT_4O)

    http_server.close
  end

  it "posts azure transcription multipart requests" do
    path = "/openai/deployments/#{Crig::Providers::Azure::GPT_4O}/audio/translations?api-version=2024-10-21"
    server = FakeAzureMultipartServer.new(path) do |_parts|
      {
        content_type: "application/json",
        body:         %({"text":"azure transcript"}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.token("azure-token"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    response = client.transcription_model(Crig::Providers::Azure::GPT_4O)
      .transcription(Crig::TranscriptionRequest.new("abc".to_slice, "speech.wav", prompt: "hint", temperature: 0.2))

    response.text.should eq("azure transcript")
    file_part = server.parts.find { |part| part[:name] == "file" }.not_nil!
    prompt_part = server.parts.find { |part| part[:name] == "prompt" }.not_nil!
    temperature_part = server.parts.find { |part| part[:name] == "temperature" }.not_nil!
    file_part[:filename].should eq("speech.wav")
    prompt_part[:body].should eq("hint")
    temperature_part[:body].should eq("0.2")
    server.headers.first["Authorization"].should eq("Bearer azure-token")

    http_server.close
  end

  it "posts azure image generation requests" do
    path = "/openai/deployments/#{Crig::Providers::Azure::GPT_4O}/images/generations?api-version=2024-10-21"
    encoded = Base64.strict_encode("azure-image")
    server = FakeAzureJsonServer.new(path) do |_request|
      {
        content_type: "application/json",
        body:         %({"created":1,"data":[{"b64_json":"#{encoded}"}]}),
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.api_key("azure-key"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    response = client.image_generation_model(Crig::Providers::Azure::GPT_4O)
      .image_generation(Crig::ImageGenerationRequest.new("A cat", 512, 512))

    String.new(response.image).should eq("azure-image")
    server.requests.first["response_format"].as_s.should eq("b64_json")

    http_server.close
  end

  it "posts azure audio generation requests" do
    path = "/openai/deployments/#{Crig::Providers::Azure::GPT_4O}/audio/speech?api-version=2024-10-21"
    server = FakeAzureJsonServer.new(path) do |_request|
      {
        content_type: "application/octet-stream",
        body:         "azure-audio",
        status_code:  nil,
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Azure::Client.builder
      .api_key(Crig::Providers::Azure::AzureOpenAIAuth.api_key("azure-key"))
      .azure_endpoint("http://127.0.0.1:#{address.port}")
      .build
    response = client.audio_generation_model(Crig::Providers::Azure::GPT_4O)
      .audio_generation(Crig::AudioGenerationRequest.new("hello", "alloy", 1.0_f32))

    String.new(response.audio).should eq("azure-audio")
    server.requests.first["voice"].as_s.should eq("alloy")

    http_server.close
  end
end
