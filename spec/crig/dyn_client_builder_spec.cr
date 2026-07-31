require "../spec_helper"
describe Crig::DynClientBuilderError, tags: %w[client_builder error] do
  it "builds parity-style dynamic client errors" do
    Crig::DynClientBuilderError.not_found("openai:gpt-4o").message.should eq("Provider 'openai:gpt-4o' not found")
    Crig::DynClientBuilderError.not_capable("openai:gpt-4o", "Completion").message.should eq("Provider 'openai:gpt-4o' cannot be coerced to a 'Completion'")
    Crig::DynClientBuilderError.completion("boom").message.should eq("Error generating response\nboom")
  end
end

describe Crig::DefaultProviders do
  it "formats provider keys like the upstream enum" do
    Crig::DefaultProviders::OpenAI.to_s.should eq("openai")
    Crig::DefaultProviders::HuggingFace.to_s.should eq("huggingface")
    Crig::DefaultProviders.all.size.should be >= 16
  end

  it "builds environment factories for default providers" do
    Crig::DefaultProviders::OpenAI.env_factory.should be_a(Crig::ProviderFactory)
  end
end

describe Crig::AnyClient do
  it "exposes supported dynamic client capabilities" do
    client = Crig::AnyClient.new(FakeCompletionClient.new)

    client.as_completion.should_not be_nil
    client.as_embedding.should be_nil
    client.as_transcription.should be_nil
    client.as_image_generation.should be_nil
    client.as_audio_generation.should be_nil
  end

  it "supports manually composed capability sets" do
    client = Crig::AnyClient.new(
      completion: FakeCompletionClient.new.as(Crig::CompletionClientDyn),
      embeddings: FakeEmbeddingsClient.new.as(Crig::EmbeddingsClientDyn),
      transcription: FakeTranscriptionClient.new.as(Crig::TranscriptionClientDyn),
      image_generation: FakeImageGenerationClient.new.as(Crig::ImageGenerationClientDyn),
      audio_generation: FakeAudioGenerationClient.new.as(Crig::AudioGenerationClientDyn),
    )

    client.as_completion.should_not be_nil
    client.as_embedding.should_not be_nil
    client.as_transcription.should_not be_nil
    client.as_image_generation.should_not be_nil
    client.as_audio_generation.should_not be_nil
  end
end

describe Crig::DynClientBuilder, tags: %w[client_builder dyn] do
  it "registers default provider env factories on construction" do
    builder = Crig::DynClientBuilder.new

    builder.factories.has_key?("openai").should be_true
    builder.factories.has_key?("anthropic").should be_true
    builder.factories.has_key?("doubleword").should be_true
  end

  it "registers and looks up provider factories by provider:model key" do
    builder = Crig::DynClientBuilder.new.register("openai", "gpt-4o") do
      Crig::AnyClient.new(FakeCompletionClient.new)
    end

    builder.factory("openai", "gpt-4o").should_not be_nil
    builder.from_env("openai", "gpt-4o").as_completion.should_not be_nil
  end

  it "falls back to provider-level env factories when no model-specific factory exists" do
    builder = Crig::DynClientBuilder.new(
      {"openai" => Crig::ProviderFactory.new(-> { Crig::AnyClient.new(FakeCompletionClient.new) })}
    )

    builder.factory("openai", "gpt-4o").should_not be_nil
    builder.from_env("openai", "gpt-4o").as_completion.should_not be_nil
  end

  it "builds completion agents and models from registered providers" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeCompletionClient.new) }

    agent = builder.agent("openai", "gpt-4o").build
    completion = builder.completion("openai", "gpt-4o")

    agent.model.should be_a(Crig::CompletionModelHandle)
    completion.completion_request(Crig::Completion::Message.user("hello")).send(completion).raw_response.should eq("raw:gpt-4o")
  end

  it "builds embedding and transcription models from registered providers" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "text-embedding-3-large") { Crig::AnyClient.new(FakeEmbeddingsClient.new) }
      .register("openai", "whisper-1") { Crig::AnyClient.new(FakeTranscriptionClient.new) }

    builder.embeddings("openai", "text-embedding-3-large").embed_text("hello").document.should eq("text-embedding-3-large:hello")
    builder.transcription("openai", "whisper-1").transcription_request.data(Bytes[1_u8]).send.response.should eq("transcription:whisper-1")
  end

  it "builds image and audio generation models from registered providers" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "dall-e-3") { Crig::AnyClient.new(FakeImageGenerationClient.new) }
      .register("openai", "tts-1") { Crig::AnyClient.new(FakeAudioGenerationClient.new) }

    builder.image_generation("openai", "dall-e-3").image_generation_request
      .prompt("draw")
      .send
      .response
      .should eq("image:dall-e-3")
    builder.audio_generation("openai", "tts-1").audio_generation_request
      .text("say hello")
      .voice("alloy")
      .send
      .response
      .should eq("audio:tts-1")
  end

  it "raises parity-style not-found errors for missing registrations" do
    builder = Crig::DynClientBuilder.new

    expect_raises(Crig::DynClientBuilderError, "Provider 'nonexistent:gpt-4o' not found") do
      builder.from_env("nonexistent", "gpt-4o")
    end
  end

  it "raises parity-style capability errors for unsupported roles" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeEmbeddingsClient.new) }

    expect_raises(Crig::DynClientBuilderError, "Provider 'openai:gpt-4o' cannot be coerced to a 'Completion'") do
      builder.agent("openai", "gpt-4o")
    end
  end

  it "streams explicit completion requests through the registered completion model" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeCompletionClient.new) }
    request = Crig::Completion::Request::CompletionRequestBuilder.from_prompt("hello").build

    response = builder.stream_completion("openai", "gpt-4o", request)

    response.chunks.should eq(["chunk:gpt-4o"])
    response.response.try(&.usage).try(&.total_tokens).should eq(3)
  end

  it "streams one-shot prompts through the registered completion model" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeCompletionClient.new) }

    response = builder.stream_prompt("openai", "gpt-4o", "hello")

    response.chunks.should eq(["chunk:gpt-4o"])
  end

  it "streams chat history by appending the prompt to the existing messages" do
    builder = Crig::DynClientBuilder.new
      .register("openai", "gpt-4o") { Crig::AnyClient.new(FakeCompletionClient.new) }
    history = [Crig::Completion::Message.user("earlier")]

    response = builder.stream_chat("openai", "gpt-4o", "hello", history)

    response.chunks.should eq(["chunk:gpt-4o"])
  end
end

describe Crig::ClientBuilderError, tags: %w[client_builder error] do
  it "builds parity-style client builder errors" do
    Crig::ClientBuilderError.http_error("boom").message.should eq("reqwest error: boom")
    Crig::ClientBuilderError.invalid_property("base_url").message.should eq("invalid property: base_url")
  end
end

describe Crig::Transport do
  it "exposes the upstream transport variants" do
    Crig::Transport.values.should eq([
      Crig::Transport::Http,
      Crig::Transport::Sse,
      Crig::Transport::NdJson,
    ])
  end
end

describe Crig::BearerAuth do
  it "builds a bearer authorization header" do
    auth = Crig::BearerAuth.new("secret")

    auth.into_header.should eq({"Authorization", "Bearer secret"})
    Crig::BearerAuth.from("token").token.should eq("token")
  end
end

describe Crig::Nothing do
  it "acts like an empty api key and rejects string conversion" do
    Crig::Nothing.new.into_header.should be_nil

    expect_raises(Exception, "Tried to create a Nothing from a string - this should not happen, please file an issue") do
      Crig::Nothing.try_from("oops")
    end
  end
end

describe Crig::Capable(String) do
  it "reports capability support" do
    Crig::Capable(String).new.capable?.should be_true
  end
end

describe Crig::Capability do
  it "supports true and false marker implementations" do
    Crig::Capable(String).new.capable?.should be_true
    Crig::Nothing.new.capable?.should be_false
  end
end

describe Crig::ProviderClient(String) do
  it "supports env and explicit value construction" do
    FakeProviderClient.from_env.source.should eq("env")
    FakeProviderClient.from_val("value").source.should eq("value")
  end
end

describe Crig::Provider(Symbol) do
  it "builds provider uris with and without trailing slashes" do
    provider = FakeProviderExtension.new

    provider.build_uri("https://api.example.com", "/verify", Crig::Transport::Http).should eq("https://api.example.com/verify")
    provider.build_uri("", "/verify", Crig::Transport::Sse).should eq("verify")
  end

  it "supports customizing request builders" do
    provider = FakeProviderExtension.new
    request = Crig::Client::RequestBuilder.new("POST", "https://api.example.com/verify")

    provider.with_custom(request).body_value.should eq("customized")
  end
end

describe Crig::DebugExt do
  it "returns no debug fields by default" do
    DefaultDebugExtExample.new.fields.should eq([] of {String, String})
  end
end

describe Crig::Capabilities do
  it "exposes capability flags on provider capability sets" do
    capabilities = FakeCapabilities.new

    capabilities.completion_capability.should be_true
    capabilities.embeddings_capability.should be_false
    capabilities.transcription_capability.should be_true
  end
end
