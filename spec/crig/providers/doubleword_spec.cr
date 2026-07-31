require "../../spec_helper"

describe Crig::Providers::Doubleword do
  it "supports client initialization" do
    client = Crig::Providers::Doubleword::Client.new("dummy-key")
    client_from_builder = Crig::Providers::Doubleword::Client.builder.api_key("dummy-key").build

    client.api_key.token.should eq("dummy-key")
    client_from_builder.api_key.token.should eq("dummy-key")
    client.base_url.should eq(Crig::Providers::Doubleword::DOUBLEWORD_API_BASE_URL)
  end

  it "exposes upstream model constants" do
    Crig::Providers::Doubleword::QWEN3_5_4B.should eq("Qwen/Qwen3.5-4B")
    Crig::Providers::Doubleword::QWEN3_5_9B.should eq("Qwen/Qwen3.5-9B")
    Crig::Providers::Doubleword::QWEN3_EMBEDDING_8B.should eq("Qwen/Qwen3-Embedding-8B")
  end

  it "builds a completion request with the shared openai-compatible shape" do
    client = Crig::Providers::Doubleword::Client.new("dummy-key")
    model = client.completion_model(Crig::Providers::Doubleword::QWEN3_5_9B)
    request = Crig::Completion::Request::CompletionRequestBuilder.new("Hello world!").build

    payload = Crig::Providers::Doubleword::DoublewordCompletionRequest.from_request(Crig::Providers::Doubleword::QWEN3_5_9B, request)
    json = JSON.parse(payload.to_json)

    json["model"].as_s.should eq("Qwen/Qwen3.5-9B")
    json["messages"][0]["role"].as_s.should eq("user")
    json["messages"][0]["content"].as_s.should eq("Hello world!")
    json["stream"].as_bool.should be_false
  end

  it "serializes tools into the completion request" do
    client = Crig::Providers::Doubleword::Client.new("dummy-key")
    request = Crig::Completion::Request::CompletionRequestBuilder.new("Use a tool.")
      .tool(Crig::Completion::ToolDefinition.new("alpha", "Alpha tool", JSON.parse(%({"type":"object","properties":{},"required":[]}))))
      .build

    payload = Crig::Providers::Doubleword::DoublewordCompletionRequest.from_request(Crig::Providers::Doubleword::QWEN3_5_9B, request)
    json = JSON.parse(payload.to_json)

    json["tools"][0]["type"].as_s.should eq("function")
    json["tools"][0]["function"]["name"].as_s.should eq("alpha")
  end

  it "posts embeddings requests and parses embeddings" do
    server = FakeOpenAIEmbeddingServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "object":"list",
          "data":[{"object":"embedding","embedding":[0.1,0.2],"index":0}],
          "model":"Qwen/Qwen3-Embedding-8B",
          "usage":{"prompt_tokens":2,"total_tokens":2}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Doubleword::Client.new("test-key", "http://127.0.0.1:#{address.port}/v1")
    model = client.embedding_model(Crig::Providers::Doubleword::QWEN3_EMBEDDING_8B)

    embeddings = model.embed_texts(["hello"])

    embeddings.first.document.should eq("hello")
    embeddings.first.vec.should eq([0.1, 0.2])
    posted = server.requests.first
    posted["model"].as_s.should eq("Qwen/Qwen3-Embedding-8B")
    posted["input"][0].as_s.should eq("hello")

    http_server.close
  end
end
