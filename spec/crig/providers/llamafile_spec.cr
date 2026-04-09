require "../../spec_helper"

describe Crig::Providers::Llamafile::Client do
  it "supports client initialization from url and model helpers" do
    client = Crig::Providers::Llamafile::Client.from_url("http://localhost:8080")

    client.completions_client.base_url.should eq("http://localhost:8080/v1")
    client.responses_client.base_url.should eq("http://localhost:8080/v1")
    client.completion_model(Crig::Providers::Llamafile::LLAMA_CPP).model.should eq(Crig::Providers::Llamafile::LLAMA_CPP)
    client.embedding_model(Crig::Providers::Llamafile::LLAMA_CPP).model.should eq(Crig::Providers::Llamafile::LLAMA_CPP)
  end

  it "posts llamafile chat completions through the OpenAI-compatible endpoint" do
    server = FakeOpenAIChatServer.new do |_request|
      {
        content_type: "application/json",
        body:         %({
          "id":"chatcmpl-1",
          "object":"chat.completion",
          "created":1710000000,
          "model":"LLaMA_CPP",
          "choices":[{"index":0,"message":{"role":"assistant","content":"hello from llamafile"},"finish_reason":"stop"}],
          "usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}
        }),
      }
    end
    http_server = server.http_server
    address = http_server.bind_tcp("127.0.0.1", 0)
    spawn { http_server.listen }

    client = Crig::Providers::Llamafile::Client.from_url("http://127.0.0.1:#{address.port}")
    response = client.completion_model(Crig::Providers::Llamafile::LLAMA_CPP)
      .completion(Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build)

    response.choice.first.text.not_nil!.text.should eq("hello from llamafile")
    server.requests.first["model"].as_s.should eq(Crig::Providers::Llamafile::LLAMA_CPP)

    http_server.close
  end
end
