require "../spec_helper"
describe Crig::VerifyError, tags: %w[verify error] do
  it "builds parity-style verification errors" do
    Crig::VerifyError.invalid_authentication.message.should eq("invalid authentication")
    Crig::VerifyError.provider_error("boom").message.should eq("provider error: boom")
    Crig::VerifyError.http_error("timeout").message.should eq("http error: timeout")
  end
end

describe Crig::VerifyClient, tags: %w[verify client] do
  it "verifies through the concrete client interface" do
    client = SuccessfulVerifyClient.new

    client.verify

    client.verified?.should be_true
  end

  it "surfaces provider verification failures" do
    client = FailingVerifyClient.new

    expect_raises(Crig::VerifyError, "provider error: boom") do
      client.verify
    end
  end

  it "verifies asynchronously through the concrete client interface" do
    client = SuccessfulVerifyClient.new

    client.verify_async.receive.unwrap

    client.verified?.should be_true
  end
end

describe Crig::VerifyClientDyn, tags: %w[verify client_dyn] do
  it "supports the dynamic verification interface" do
    client = SuccessfulVerifyClient.new.as(Crig::VerifyClientDyn)

    client.verify
  end

  it "supports asynchronous dynamic verification" do
    client = SuccessfulVerifyClient.new.as(Crig::VerifyClientDyn)

    client.verify_async.receive.unwrap
  end
end

describe Crig::EmbeddingsClient(FakeEmbeddingsClientModel), tags: %w[embeddings client] do
  it "builds embedding models and builders through the client interface" do
    client = FakeEmbeddingsClient.new
    model = client.embedding_model("test-model")
    builder = client.embeddings(ExampleEmbedding, "test-model").document(ExampleEmbedding.new(["hello"]))

    model.name.should eq("test-model")
    builder.model.name.should eq("test-model")
    builder.build[0][1].first.document.should eq("test-model:hello")
  end

  it "supports the rust-style embeddings builder entry point without a type argument" do
    client = FakeEmbeddingsClient.new
    builder = client.embeddings("test-model")
      .simple_document("doc0", "Hello, world!")
      .simple_document("doc1", "Goodbye, world!")

    builder.model.name.should eq("test-model")
    builder.documents.map(&.[0].id).should eq(["doc0", "doc1"])
    builder.build.map { |entry| entry[1].first.document }.should eq(
      ["test-model:Hello, world!", "test-model:Goodbye, world!"]
    )
  end

  it "supports explicit embedding dimensions" do
    client = FakeEmbeddingsClient.new
    model = client.embedding_model_with_ndims("test-model", 42)
    builder = client.embeddings_with_ndims(ExampleEmbedding, "test-model", 42).document(ExampleEmbedding.new(["hello"]))

    model.ndims.should eq(42)
    builder.model.ndims.should eq(42)
  end

  it "supports the rust-style embeddings_with_ndims builder entry point without a type argument" do
    client = FakeEmbeddingsClient.new
    builder = client.embeddings_with_ndims("test-model", 42)
      .simple_document("doc0", "Hello, world!")

    builder.model.ndims.should eq(42)
    builder.build[0][1].first.document.should eq("test-model:Hello, world!")
  end
end

describe Crig::EmbeddingsClientDyn, tags: %w[embeddings client_dyn] do
  it "returns dynamic embedding models" do
    client = FakeEmbeddingsClient.new.as(Crig::EmbeddingsClientDyn)
    model = client.embedding_model("test-model")

    model.embed_text("hello").document.should eq("test-model:hello")
    client.embedding_model_with_ndims("test-model", 42).ndims.should eq(42)
  end
end

describe Crig::CompletionClient(FakeCompletionClientModel), tags: %w[completion client] do
  it "builds completion models and agent builders through the client interface" do
    client = FakeCompletionClient.new
    model = client.completion_model("gpt-4o")
    agent = client.agent("gpt-4o")
      .description("assistant")
      .preamble("You are concise.")
      .append_preamble("Be brief.")
      .context("Fact A")
      .default_max_turns(3)
      .temperature(0.2)
      .build
    response = agent.model.completion_request("hello").send(agent.model)

    model.name.should eq("gpt-4o")
    response.raw_response.should eq("raw:gpt-4o")
    agent.description.should eq("assistant")
    agent.preamble.should eq("You are concise.\nBe brief.")
    agent.static_context.map(&.text).should eq(["Fact A"])
    agent.default_max_turns.should eq(3)
    agent.temperature.should eq(0.2)
  end

  it "builds extractor builders through the client interface" do
    client = FakeCompletionClient.new
    extractor = client.extractor(String, "gpt-4o")
      .preamble("Only extract weather.")
      .context("Denver forecast")
      .additional_params(JSON.parse(%({"mode":"strict"})))
      .max_tokens(128)
      .tool_choice(Crig::Completion::ToolChoice.auto)
      .retries(2)
      .build
    response = extractor.model.completion_request("hello").send(extractor.model)

    response.raw_response.should eq("raw:gpt-4o")
    extractor.retries.should eq(2)
    extractor.agent.preamble.try(&.includes?("ADDITIONAL INSTRUCTIONS")).should be_true
    extractor.agent.static_context.map(&.text).should eq(["Denver forecast"])
    extractor.agent.additional_params.try(&.["mode"].as_s).should eq("strict")
    extractor.agent.max_tokens.should eq(128)
    extractor.agent.tool_choice.should eq(Crig::Completion::ToolChoice.auto)
  end
end

describe Crig::CompletionClientDyn, tags: %w[completion client_dyn] do
  it "builds dynamic completion models" do
    client = FakeCompletionClient.new.as(Crig::CompletionClientDyn)
    model = client.completion_model("gpt-4o")
    response = model.completion_request(Crig::Completion::Message.user("hello")).send(model)

    response.raw_response.should eq("raw:gpt-4o")
  end

  it "builds dynamic agent builders backed by completion handles" do
    client = FakeCompletionClient.new.as(Crig::CompletionClientDyn)
    agent = client.agent("gpt-4o").name("assistant").build

    agent.model.should be_a(Crig::CompletionModelHandle)
    agent.name.should eq("assistant")
  end
end

describe Crig::CompletionModelHandle, tags: %w[completion model_handle] do
  it "wraps a dynamic completion model for request and stream builders" do
    inner = FakeCompletionClientModel.new("gpt-4o").as(Crig::Completion::CompletionModelDyn)
    handle = Crig::CompletionModelHandle.new(inner)
    completion = handle.completion_request("hello").send(handle)
    stream = handle.completion_request("hello").stream(handle)

    completion.raw_response.should eq("raw:gpt-4o")
    stream.chunks.should eq(["chunk:gpt-4o"])
    stream.response.try(&.usage).try(&.total_tokens).should eq(3)
  end

  it "rejects direct construction from a client" do
    expect_raises(Exception, "Cannot create a completion model handle from a client") do
      Crig::CompletionModelHandle.make(nil, "gpt-4o")
    end
  end
end

describe Crig::FinalCompletionResponse, tags: %w[completion response] do
  it "exposes token usage for dynamic streaming parity" do
    response = Crig::FinalCompletionResponse.new(Crig::Completion::Usage.new(total_tokens: 4))

    response.token_usage.try(&.total_tokens).should eq(4)
  end

  it "round-trips optional usage through json" do
    response = Crig::FinalCompletionResponse.from_json(%({"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3,"cached_input_tokens":0}}))

    response.usage.try(&.total_tokens).should eq(3)
    response.to_json.should contain(%("total_tokens":3))
  end
end
